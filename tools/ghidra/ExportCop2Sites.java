// Export addresses of every disassembled COP2 instruction (MFC2/CFC2/MTC2/CTC2/LWC2/SWC2/GTE ops).
// Usage (headless): -postScript ExportCop2Sites.java <output_dir>
// Writes <output_dir>/<program>.cop2.txt with one hex address per line.
//@category Tekken3

import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

public class ExportCop2Sites extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		File outDir = new File(args.length > 0 ? args[0] : ".");
		outDir.mkdirs();
		int count = 0;
		try (PrintWriter out = new PrintWriter(new File(outDir, currentProgram.getName() + ".cop2.txt"))) {
			InstructionIterator it = currentProgram.getListing().getInstructions(true);
			while (it.hasNext()) {
				Instruction ins = it.next();
				byte[] b = ins.getBytes();
				// PSX GTE macros can span several 32-bit words; check each word.
				for (int off = 0; off + 4 <= b.length; off += 4) {
					int word = (b[off] & 0xff) | (b[off + 1] & 0xff) << 8 | (b[off + 2] & 0xff) << 16
							| (b[off + 3] & 0xff) << 24;
					int op = word >>> 26;
					if (op == 0x12 || op == 0x32 || op == 0x3a) {
						out.println(ins.getAddress().add(off).toString());
						count++;
					}
				}
			}
		}
		println("cop2 sites: " + count);
	}
}
