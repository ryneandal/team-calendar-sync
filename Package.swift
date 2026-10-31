// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeamCalendar",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CalendarCore", targets: ["CalendarCore"]),
        .executable(name: "TeamCalendar", targets: ["TeamCalendar"]),
    ],
    targets: [
        .target(name: "CalendarCore", resources: [.process("Resources")]),
        .executableTarget(name: "TeamCalendar", dependencies: ["CalendarCore"]),
        .testTarget(name: "CalendarCoreTests", dependencies: ["CalendarCore"]),
        .testTarget(name: "TeamCalendarTests", dependencies: ["TeamCalendar"]),
    ]
)
