import Foundation

enum CalculatorError: LocalizedError, Equatable {
    case divisionByZero
    case invalidExpression
    case resultOutOfRange

    var errorDescription: String? {
        switch self {
        case .divisionByZero: "不能除以 0"
        case .invalidExpression: "请检查算式"
        case .resultOutOfRange: "计算结果超出可记金额范围"
        }
    }
}

struct CalculatorEngine {
    enum Operator: String {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"

        var symbol: String {
            switch self {
            case .add: "+"
            case .subtract: "−"
            case .multiply: "×"
            case .divide: "÷"
            }
        }
    }

    private enum Token {
        case number(Decimal)
        case operation(Operator)
    }

    private(set) var current = "0"
    private(set) var equation = ""
    private var tokens: [Token] = []
    private var justEvaluated = false

    static let maximumAmount = Decimal(string: "999999999.99")!

    var display: String {
        if !current.isEmpty { return current }
        if tokens.count >= 2, case let .number(value)? = tokens.dropLast().last {
            return Formatters.decimal(value)
        }
        return "0"
    }

    var formula: String {
        if !equation.isEmpty { return equation }
        guard !tokens.isEmpty else { return "输入金额，可混合计算" }
        return expression(tokens + (current.isEmpty ? [] : [.number(Decimal(string: current) ?? 0)]))
    }

    mutating func input(_ key: String) {
        guard key.count == 1, "0123456789.".contains(key) else { return }
        if justEvaluated { clear() }

        if key == "." {
            if current.contains(".") { return }
            current = current.isEmpty || current == "0" ? "0." : current + "."
            equation = ""
            return
        }

        if current == "0" || current.isEmpty {
            current = key
        } else {
            let components = current.split(separator: ".", omittingEmptySubsequences: false)
            if components.count == 2 && components[1].count >= 2 { return }
            if components[0].count >= 10 { return }
            current += key
        }
        equation = ""
    }

    mutating func append(_ operation: Operator) {
        equation = ""
        justEvaluated = false
        if current.isEmpty || current == "." {
            if tokens.count >= 2, case .operation = tokens.last {
                tokens[tokens.count - 1] = .operation(operation)
            }
            return
        }
        guard tokens.count < 31, let value = Decimal(string: current) else { return }
        tokens.append(.number(value))
        tokens.append(.operation(operation))
        current = ""
    }

    @discardableResult
    mutating func evaluate() throws -> Decimal {
        guard !tokens.isEmpty else {
            guard let value = Decimal(string: current), value.isFinite else {
                throw CalculatorError.invalidExpression
            }
            return Formatters.rounded(value)
        }

        var work = tokens
        if current.isEmpty {
            if case .operation = work.last { work.removeLast() }
        } else if let value = Decimal(string: current) {
            work.append(.number(value))
        }

        guard work.count >= 3, case let .number(first)? = work.first else {
            throw CalculatorError.invalidExpression
        }

        var stack: [Decimal] = [first]
        var index = 1
        while index + 1 < work.count {
            guard case let .operation(operation) = work[index],
                  case let .number(number) = work[index + 1] else {
                throw CalculatorError.invalidExpression
            }
            switch operation {
            case .multiply:
                stack[stack.count - 1] *= number
            case .divide:
                guard number != 0 else { throw CalculatorError.divisionByZero }
                stack[stack.count - 1] /= number
            case .add:
                stack.append(number)
            case .subtract:
                stack.append(-number)
            }
            index += 2
        }

        guard index == work.count else { throw CalculatorError.invalidExpression }
        let result = Formatters.rounded(stack.reduce(0, +))
        guard result.isFinite else { throw CalculatorError.invalidExpression }
        guard abs(result) <= Self.maximumAmount else { throw CalculatorError.resultOutOfRange }

        equation = expression(work) + " ="
        current = Formatters.decimal(result)
        tokens = []
        justEvaluated = true
        return result
    }

    mutating func backspace() {
        if justEvaluated {
            clear()
            return
        }
        equation = ""
        if current.isEmpty, case .operation = tokens.last {
            tokens.removeLast()
            if case let .number(value)? = tokens.last {
                current = Formatters.decimal(value)
                tokens.removeLast()
            }
            return
        }
        if current.count > 1 {
            current.removeLast()
        } else {
            current = tokens.isEmpty ? "0" : ""
        }
    }

    mutating func clear() {
        current = "0"
        equation = ""
        tokens = []
        justEvaluated = false
    }

    private func expression(_ tokens: [Token]) -> String {
        tokens.map { token in
            switch token {
            case .number(let value): Formatters.decimal(value)
            case .operation(let operation): operation.symbol
            }
        }.joined(separator: " ")
    }
}
