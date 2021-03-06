enum Opcode: String {
	case addr, addi, mulr, muli, banr, bani, borr, bori, setr, seti, gtir, gtri, gtrr, eqir, eqri, eqrr
}

extension Sequence {
	var tuple4: (Element, Element, Element, Element)? {
		var iter = makeIterator()
		guard let first  = iter.next(),
		      let second = iter.next(),
		      let third  = iter.next(),
		      let fourth = iter.next()
		else { return nil }
		return (first, second, third, fourth)
	}
}

struct Instruction {
	var opcode: Opcode
	var a: Int
	var b: Int
	var c: Int
	init?<S: Sequence>(_ seq: S) where S.Element == Substring {
		guard let (opcodestr, astr, bstr, cstr) = seq.tuple4 else { return nil }
		guard let opcode = Opcode(rawValue: String(opcodestr)), let a = Int(astr), let b = Int(bstr), let c = Int(cstr) else { return nil }
		(self.opcode, self.a, self.b, self.c) = (opcode, a, b, c)
	}
}

extension Instruction: CustomStringConvertible {
	var description: String {
		return "\(opcode.rawValue) \(a) \(b) \(c)"
	}
}

extension Instruction {
	func cOp(ip: Int, index: Int) -> String {
		let ra = a == ip ? "\(index)" : "r[\(a)]"
		let rb = b == ip ? "\(index)" : "r[\(b)]"
		switch opcode {
		case .addr: return "\(ra) + \(rb)"
		case .addi: return "\(ra) + \(b)"
		case .mulr: return "\(ra) * \(rb)"
		case .muli: return "\(ra) * \(b)"
		case .banr: return "\(ra) & \(rb)"
		case .bani: return "\(ra) & \(b)"
		case .borr: return "\(ra) | \(rb)"
		case .bori: return "\(ra) | \(b)"
		case .setr: return "\(ra)"
		case .seti: return "\(a)"
		case .gtir: return "\(a) > \(rb) ? 1 : 0"
		case .gtri: return "\(ra) > \(b) ? 1 : 0"
		case .gtrr: return "\(ra) > \(rb) ? 1 : 0"
		case .eqir: return "\(a) == \(rb) ? 1 : 0"
		case .eqri: return "\(ra) == \(b) ? 1 : 0"
		case .eqrr: return "\(ra) == \(rb) ? 1 : 0"
		}
	}
}

func makeC(_ input: [Instruction], ip: Int, jumpTargets: [Int]) -> String {
	func finalizingStatement(str pos: String) -> String {
		return "r[\(ip)] = \(pos); printRegs(r); return 0;"
	}
	func finalizingStatement(at pos: Int) -> String {
		return finalizingStatement(str: String(pos))
	}
	let doJumpMacro = """
		#define doJump(x, line) switch (x) { \(input[1...].indices.lazy.map({ "case \($0-1): goto l\($0);" }).joined(separator: " ")) default: \(finalizingStatement(str: "(line)")) }
		"""
	let badJumpMacro = """
		#define badJump(line, reg) if (1) { fprintf(stderr, "Made a jump at l%d with an unsupported offset of %ld.  Transpile with -allJumps to enable full jump support.\\n", (line), (reg)); abort(); }
		"""
	var finalOutput = """
		#include <stdlib.h>
		#include <stdio.h>
		\(jumpTargets.isEmpty ? doJumpMacro : badJumpMacro)
		void printRegs(long *r) {
			printf("%ld %ld %ld %ld %ld %ld\\n", r[0], r[1], r[2], r[3], r[4], r[5]);
		}
		int main(int argc, char **argv) {
			long r[6] = {0};
			for (int i = 0; i < (argc > 6 ? 6 : argc - 1); i++) {
				r[i] = atoi(argv[i+1]);
			}\n
		"""

	func makeGoto(_ target: Int, index: Int) -> String {
		if input.indices.contains(target) {
			return "goto l\(target);"
		}
		else {
			return finalizingStatement(at: index)
		}
	}
		
	func makeJump(_ str: String, index: Int, targets: [Int]) -> String {
		let others = targets.lazy.map { "else if (\(str) == \($0)) { \(makeGoto(index + $0 + 1, index: index)) }" }.joined(separator: " ")
		return "if (\(str) == 0) { goto l\(index+1); } \(others) else { badJump(\(index), \(str)); }"
	}

	let lines = input.enumerated().map { (pair) -> String in
		let (index, instr) = pair
		if instr.c == ip {
			let jump = "doJump(\(instr.cOp(ip: ip, index: index)), \(index))"
			switch (instr.opcode, instr.a, instr.b) {
			case (.addr, instr.c, instr.c):
				return makeGoto(index * 2 + 1, index: index)
			case (.addr, instr.c, _):
				return jumpTargets.isEmpty ? jump : makeJump("r[\(instr.b)]", index: index, targets: jumpTargets)
			case (.addr, _, instr.c):
				return jumpTargets.isEmpty ? jump : makeJump("r[\(instr.a)]", index: index, targets: jumpTargets)
			case (.addi, instr.c, _):
				return makeGoto(index + instr.b + 1, index: index)
			case (.muli, instr.c, _):
				return makeGoto(index * instr.b + 1, index: index)
			case (.mulr, instr.c, instr.c):
				return makeGoto(index * index + 1, index: index)
			case (.seti, _, _):
				return makeGoto(instr.a + 1, index: index)
			default:
				if !jumpTargets.isEmpty {
					FileHandle.standardError.write("Unsupported jump operation: \(instr), maybe add -allJumps to switch to all jumps mode?\n".data(using: .utf8)!)
					exit(EXIT_FAILURE)
				}
				return jump
			}
		}
		else {
			return "r[\(instr.c)] = \(instr.cOp(ip: ip, index: index));"
		}
	}

	for (index, line) in lines.enumerated() {
		finalOutput += "\tl\(index): "
		finalOutput += line
		finalOutput += "\n"
	}
	finalOutput += "\t"
	finalOutput += finalizingStatement(at: input.count - 1)
	finalOutput += "\n}"
	return finalOutput
}

import Foundation

guard CommandLine.arguments.count > 1 else {
	print("""
		Usage: \(CommandLine.arguments[0]) aocProgram.txt [-allJumps] > aocProgram.c

		If run without `-allJumps`, only some jump operations will be allowed,
		and offset-based jumps will be limited to 0 or 1 (the output of gt and eq checks)
		Otherwise, all jumps will be allowed, which may reduce the quality of
		the C compiler's output

		You can also specify a custom list of offset-based jumps with `-jumps 1 3 8 etc`

		The outputted C program can be run with anywhere from 0 to 6 arguments,
		representing the starting registers.  Registers not passed will start a 0
		""")
	exit(EXIT_FAILURE)
}

let str = try! String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))

let split = str.split(separator: "\n")
let binding = Int(split.first!.split(separator: " ")[1])!

let input = split.compactMap { line in
	return Instruction(line.split(separator: " "))
}

let allJumps = CommandLine.arguments[1...].lazy.map({ $0.lowercased() }).contains("-alljumps")
var jumps = [1]
if allJumps {
	jumps = []
}
else if let offset = CommandLine.arguments[1...].lazy.map({ $0.lowercased() }).firstIndex(of: "-jumps") {
	jumps = CommandLine.arguments[(offset + 1)...].map { if let a = Int($0) { return a } else { fatalError("Jump value \($0) must be an integer") } }
}

print(makeC(input, ip: binding, jumpTargets: jumps))
