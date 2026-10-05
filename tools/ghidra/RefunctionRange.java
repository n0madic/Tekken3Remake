// Rebuild the functions of an overlay address range and export their decompiled C.
// Resident code calls fixed entry points of *every* mode overlay, so an overlay program
// imported on top of the executable image inherits function starts that belong to other
// overlays and cut its real functions into fragments; screen overlays also carry large data
// blocks that must not be disassembled. This script clears the listing of [start, end), seeds
// functions at stack-frame prologues (addiu sp, sp, -N followed by sw ra) and at resident jal
// targets that begin with such a prologue within a few words, follows the code
// flow from them, adds the targets of jal instructions found in that code until nothing new
// appears, creates the functions and writes <program>.overlay.c / .overlay.functions.tsv.
// Usage (headless, -process <program> -noanalysis): -postScript RefunctionRange.java start end outDir [seeds]
// where seeds is an optional comma-separated list of extra entry points (computed jumps, callbacks).
//@category Tekken3

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.TreeSet;

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.mem.Memory;

public class RefunctionRange extends GhidraScript {
	private static final int PROLOGUE_WINDOW = 32;     // words searched for sw ra after the prologue
	private static final int ENTRY_WINDOW = 8;         // words searched for the prologue at a resident call target
	private static final long RESIDENT_START = 0x80010000L;
	private static final int DECOMPILE_TIMEOUT = 60;   // seconds

	private long start;
	private long end;

	private boolean inRange(long a) {
		return a >= start && a < end && (a & 3) == 0;
	}

	private boolean isPrologue(Memory mem, long a) throws Exception {
		int w = mem.getInt(toAddr(a));
		if ((w >>> 16) != 0x27BD || (short) (w & 0xFFFF) >= 0) {
			return false;
		}
		for (int k = 1; k <= PROLOGUE_WINDOW && a + 4 * k + 4 <= end; k++) {
			if ((mem.getInt(toAddr(a + 4 * k)) >>> 16) == 0xAFBF) {
				return true;
			}
		}
		return false;
	}

	private DecompInterface openDecompiler() {
		DecompInterface decomp = new DecompInterface();
		decomp.setOptions(new DecompileOptions());
		decomp.openProgram(currentProgram);
		return decomp;
	}

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		start = Long.decode(args[0]);
		end = Long.decode(args[1]);
		File outDir = new File(args[2]);
		AddressSet range = new AddressSet(toAddr(start), toAddr(end - 1));
		FunctionManager fm = currentProgram.getFunctionManager();
		Memory mem = currentProgram.getMemory();

		List<Address> old = new ArrayList<>();
		Iterator<Function> it = fm.getFunctionsOverlapping(range);
		while (it.hasNext()) {
			old.add(it.next().getEntryPoint());
		}
		for (Address a : old) {
			fm.removeFunction(a);
		}
		clearListing(range);

		TreeSet<Long> starts = new TreeSet<>();
		if (args.length > 3 && !args[3].isEmpty()) {
			for (String seed : args[3].split(",")) {
				starts.add(Long.decode(seed.trim()));
			}
		}
		for (long a = start; a + 4 <= end; a += 4) {
			if (isPrologue(mem, a)) {
				starts.add(a);
			}
		}
		// Entry points called by resident code (state handlers, hooks) may load registers
		// before the prologue; accept a call target with a prologue among its first words.
		for (long a = RESIDENT_START; a + 4 <= start; a += 4) {
			Address addr = toAddr(a);
			if (!mem.getLoadedAndInitializedAddressSet().contains(addr)) {
				continue;
			}
			int w = mem.getInt(addr);
			if ((w >>> 26) != 3) {
				continue;
			}
			long t = 0x80000000L | ((long) (w & 0x03FFFFFF) << 2);
			if (!inRange(t)) {
				continue;
			}
			for (int k = 0; k < ENTRY_WINDOW && t + 4 * k + 4 <= end; k++) {
				if (isPrologue(mem, t + 4 * k)) {
					starts.add(t);
					break;
				}
			}
		}

		TreeSet<Long> pending = new TreeSet<>(starts);
		while (!pending.isEmpty()) {
			AddressSet seeds = new AddressSet();
			for (long s : pending) {
				seeds.add(toAddr(s));
			}
			pending.clear();
			new DisassembleCommand(seeds, null, true).applyTo(currentProgram, monitor);
			InstructionIterator ii = currentProgram.getListing().getInstructions(range, true);
			while (ii.hasNext()) {
				Instruction ins = ii.next();
				if (!ins.getMnemonicString().equals("jal")) {
					continue;
				}
				for (Address t : ins.getFlows()) {
					long v = t.getOffset();
					if (inRange(v) && starts.add(v)) {
						pending.add(v);
					}
				}
			}
		}
		// A prologue a few words after a call target belongs to that function (registers are loaded
		// before the stack frame is set up); drop it unless a `jr ra` separates the two.
		TreeSet<Long> merged = new TreeSet<>();
		for (long s : starts) {
			Long prev = merged.isEmpty() ? null : merged.last();
			boolean inside = false;
			if (prev != null && s - prev <= 4 * ENTRY_WINDOW && isPrologue(mem, s)) {
				inside = true;
				for (long a = prev; a < s; a += 4) {
					if (mem.getInt(toAddr(a)) == 0x03E00008) {
						inside = false;
						break;
					}
				}
			}
			if (!inside) {
				merged.add(s);
			}
		}
		starts = merged;
		for (long s : starts) {
			new CreateFunctionCmd(toAddr(s)).applyTo(currentProgram, monitor);
		}
		// Recover jump tables (switch statements) of the new functions.
		analyzeChanges(currentProgram);

		DecompInterface decomp = openDecompiler();
		String base = currentProgram.getName();
		try (PrintWriter tsv = new PrintWriter(new File(outDir, base + ".overlay.functions.tsv"));
				PrintWriter c = new PrintWriter(new File(outDir, base + ".overlay.c"))) {
			tsv.println("address\tname\tbody_bytes\tcallers");
			for (long s : starts) {
				Function f = fm.getFunctionAt(toAddr(s));
				if (f == null) {
					continue;
				}
				tsv.printf("%s\t%s\t%d\t%d%n", f.getEntryPoint(), f.getName(),
					f.getBody().getNumAddresses(), f.getCallingFunctions(monitor).size());
				DecompileResults res = decomp.decompileFunction(f, DECOMPILE_TIMEOUT, monitor);
				if (res == null || !res.decompileCompleted()) {
					// A crashed decompiler process fails every later call; restart it and retry once.
					decomp.dispose();
					decomp = openDecompiler();
					res = decomp.decompileFunction(f, DECOMPILE_TIMEOUT, monitor);
				}
				c.printf("%n// ===== %s @ %s =====%n", f.getName(), f.getEntryPoint());
				if (res != null && res.decompileCompleted()) {
					c.print(res.getDecompiledFunction().getC());
				} else {
					c.printf("// decompilation failed: %s%n", res == null ? "null" : res.getErrorMessage());
				}
			}
		}
		decomp.dispose();
	}
}
