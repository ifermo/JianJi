import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv
    case excel

    var id: String { rawValue }
    var title: String { self == .csv ? "CSV" : "Excel XML" }
    var fileExtension: String { self == .csv ? "csv" : "xml" }
}

struct ExportService {
    func makeFile(
        transactions: [LedgerTransaction],
        categories: [LedgerCategory],
        format: ExportFormat
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let rows = transactions.sorted { $0.date > $1.date }.map { transaction -> [String] in
            let category = categories.first { $0.id == transaction.categoryID }?.name ?? (transaction.type == .transfer ? "转账" : "未分类")
            return [
                transaction.type.title,
                formatter.string(from: transaction.date),
                transaction.merchant,
                category,
                Formatters.decimal(transaction.amount),
                transaction.note,
                transaction.sourceAccount ?? "",
                transaction.destinationAccount ?? ""
            ]
        }
        let header = ["类型", "日期", "商户", "分类", "金额", "备注", "转出账户", "转入账户"]
        let content = format == .csv ? csv(header: header, rows: rows) : spreadsheet(header: header, rows: rows)
        let stamp = DateFormatter.fileStamp.string(from: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("简记账单_\(stamp).\(format.fileExtension)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func csv(header: [String], rows: [[String]]) -> String {
        let body = ([header] + rows).map { row in
            row.map { field in
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }.joined(separator: ",")
        }.joined(separator: "\r\n")
        return "\u{FEFF}" + body
    }

    private func spreadsheet(header: [String], rows: [[String]]) -> String {
        func xmlRow(_ values: [String]) -> String {
            "<Row>" + values.map { "<Cell><Data ss:Type=\"String\">\($0.xmlEscaped)</Data></Cell>" }.joined() + "</Row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="简记账单"><Table>\(xmlRow(header))\(rows.map(xmlRow).joined())</Table></Worksheet>
        </Workbook>
        """
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
