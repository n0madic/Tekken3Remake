// Apply project annotations (types, function names/prototypes, data labels, comments).
// Usage (headless): -postScript ApplyAnnotations.java <tekken3.h> <symbols.txt>
//
// symbols.txt line format (whitespace separated, '#' starts a comment line):
//   func  <hex_addr> <name> [C prototype ... ;]
//   data  <hex_addr> <name> [type name]  [count]
//   cmt   <hex_addr> <plate comment text ...>
// Entries whose address is not initialized memory in the current program are skipped,
// so one file can serve the resident EXE and every overlay program. A directive may be
// scoped to programs whose name contains a word, e.g. "func@title 800d4f68 Name".
// Unscoped entries describe Japan Rev.1 and are not applied to the USA program (SLUS...).
//@category Tekken3

import java.io.File;
import java.nio.file.Files;
import java.util.List;

import ghidra.app.cmd.function.ApplyFunctionSignatureCmd;
import ghidra.app.script.GhidraScript;
import ghidra.app.util.cparser.C.CParser;
import ghidra.app.util.parser.FunctionSignatureParser;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.ArrayDataType;
import ghidra.program.model.data.DataType;
import ghidra.program.model.data.DataTypeConflictHandler;
import ghidra.program.model.data.DataTypeManager;
import ghidra.program.model.data.FunctionDefinitionDataType;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.data.CategoryPath;
import ghidra.program.model.data.DataTypePath;

public class ApplyAnnotations extends GhidraScript {
	private DataTypeManager dtm;

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		dtm = currentProgram.getDataTypeManager();
		if (args.length > 0 && !args[0].isEmpty()) {
			parseHeader(new File(args[0]));
		}
		if (args.length > 1) {
			applySymbols(Files.readAllLines(new File(args[1]).toPath()));
		}
	}

	private void parseHeader(File header) throws Exception {
		String text = Files.readString(header.toPath());
		CParser parser = new CParser(dtm, true, null);
		parser.parse(text);
		int count = 0;
		for (DataType dt : parser.getComposites().values()) {
			dtm.addDataType(dt, DataTypeConflictHandler.REPLACE_HANDLER);
			count++;
		}
		for (DataType dt : parser.getTypes().values()) {
			dtm.addDataType(dt, DataTypeConflictHandler.REPLACE_HANDLER);
			count++;
		}
		for (DataType dt : parser.getEnums().values()) {
			dtm.addDataType(dt, DataTypeConflictHandler.REPLACE_HANDLER);
			count++;
		}
		println("types applied: " + count);
	}

	private DataType findType(String name) {
		List<DataType> found = new java.util.ArrayList<>();
		dtm.findDataTypes(name, found);
		if (found.isEmpty()) {
			return null;
		}
		return found.get(0);
	}

	private void applySymbols(List<String> lines) throws Exception {
		int funcs = 0, datas = 0, cmts = 0, skipped = 0;
		for (String raw : lines) {
			String line = raw.strip();
			if (line.isEmpty() || line.startsWith("#")) {
				continue;
			}
			String[] parts = line.split("\\s+", 4);
			if (parts.length < 3) {
				printerr("bad line: " + line);
				continue;
			}
			String[] directive = parts[0].split("@", 2);
			boolean usaProgram = currentProgram.getName().startsWith("SLUS");
			if ((directive.length > 1 && !currentProgram.getName().contains(directive[1]))
					|| (directive.length == 1 && usaProgram)) {
				skipped++;
				continue;
			}
			Address addr = toAddr(Long.parseLong(parts[1], 16));
			if (!currentProgram.getMemory().getLoadedAndInitializedAddressSet().contains(addr)) {
				skipped++;
				continue;
			}
			switch (directive[0]) {
				case "func": {
					Function f = getFunctionAt(addr);
					if (f == null) {
						disassemble(addr);
						f = createFunction(addr, parts[2]);
					}
					if (f == null) {
						printerr("cannot create function at " + addr);
						continue;
					}
					f.setName(parts[2], SourceType.USER_DEFINED);
					if (parts.length > 3) {
						applyPrototype(f, parts[3]);
					}
					funcs++;
					break;
				}
				case "data": {
					getSymbolAt(addr);
					createLabel(addr, parts[2], true, SourceType.USER_DEFINED);
					if (parts.length > 3) {
						String[] typeSpec = parts[3].split("\\s+");
						DataType dt = findType(typeSpec[0]);
						if (dt == null) {
							printerr("unknown type " + typeSpec[0] + " for " + parts[2]);
						} else {
							if (typeSpec.length > 1) {
								int n = Integer.decode(typeSpec[1]);
								dt = new ArrayDataType(dt, n, dt.getLength());
							}
							clearListing(addr, addr.add(dt.getLength() - 1));
							createData(addr, dt);
						}
					}
					datas++;
					break;
				}
				case "cmt": {
					String text = line.split("\\s+", 3)[2];
					currentProgram.getListing().setComment(addr, CodeUnit.PLATE_COMMENT, text);
					cmts++;
					break;
				}
				default:
					printerr("unknown directive: " + line);
			}
		}
		println(String.format("functions %d, data %d, comments %d, skipped %d", funcs, datas, cmts, skipped));
	}

	private void applyPrototype(Function f, String proto) {
		try {
			FunctionSignatureParser p = new FunctionSignatureParser(dtm, null);
			FunctionDefinitionDataType sig = p.parse(f.getSignature(), proto.replace(";", ""));
			ApplyFunctionSignatureCmd cmd = new ApplyFunctionSignatureCmd(f.getEntryPoint(), sig, SourceType.USER_DEFINED);
			if (!cmd.applyTo(currentProgram, monitor)) {
				printerr("prototype failed for " + f.getName() + ": " + cmd.getStatusMsg());
			}
		} catch (Exception e) {
			printerr("prototype parse error for " + f.getName() + ": " + e.getMessage());
		}
	}
}
