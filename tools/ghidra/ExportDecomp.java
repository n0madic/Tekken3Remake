// Export function list and decompiled C for every function in the current program.
// Usage (headless): -postScript ExportDecomp.java <output_dir>
// Writes <output_dir>/<program>.functions.tsv and <output_dir>/<program>.c
//@category Tekken3

import java.io.File;
import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;

public class ExportDecomp extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		File outDir = new File(args.length > 0 ? args[0] : ".");
		outDir.mkdirs();
		String base = currentProgram.getName();

		DecompInterface decomp = new DecompInterface();
		decomp.setOptions(new DecompileOptions());
		decomp.openProgram(currentProgram);

		try (PrintWriter tsv = new PrintWriter(new File(outDir, base + ".functions.tsv"));
				PrintWriter c = new PrintWriter(new File(outDir, base + ".c"))) {
			tsv.println("address\tname\tbody_bytes\tcallers");
			FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
			while (it.hasNext() && !monitor.isCancelled()) {
				Function f = it.next();
				tsv.printf("%s\t%s\t%d\t%d%n", f.getEntryPoint(), f.getName(),
					f.getBody().getNumAddresses(), f.getCallingFunctions(monitor).size());
				DecompileResults res = decomp.decompileFunction(f, 60, monitor);
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
