import SwiftUI

struct HierarchicalDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Binding var selectedDate: Date
    @Binding var mode: CalendarMode
    @State private var level: HierarchicalDatePickerLevel = .month
    @State private var visibleMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let yearColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    init(selectedDate: Binding<Date>, mode: Binding<CalendarMode>) {
        _selectedDate = selectedDate
        _mode = mode
        _visibleMonth = State(
            initialValue: HierarchicalDatePickerPlan.normalizedMonth(containing: selectedDate.wrappedValue)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch level {
                case .month:
                    monthView
                case .months:
                    monthsView
                case .years:
                    yearsView
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(settings.strings.datePickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.strings.cancelButton) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var monthView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    level = .months
                } label: {
                    Text(visibleMonth, format: .dateTime.month(.wide))
                        .font(.headline)
                }

                Button {
                    level = .years
                } label: {
                    Text(yearText(for: visibleMonth))
                        .font(.headline)
                }

                Spacer()

                Button {
                    moveMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)

                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(HierarchicalDatePickerPlan.monthGrid(containing: visibleMonth)) { day in
                    let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                    Button {
                        selectDay(day.date)
                    } label: {
                        Text(day.date, format: .dateTime.day())
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(dayTextColor(day: day, isSelected: isSelected))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthsView: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    level = .years
                } label: {
                    Text(yearText(for: visibleMonth))
                        .font(.headline)
                }

                Spacer()
            }

            LazyVGrid(columns: monthColumns, spacing: 10) {
                ForEach(HierarchicalDatePickerPlan.months(inYearContaining: visibleMonth), id: \.self) { month in
                    Button {
                        let navigation = HierarchicalDatePickerPlan.selectMonth(month)
                        visibleMonth = navigation.visibleMonth
                        level = navigation.level
                    } label: {
                        Text(month, format: .dateTime.month(.abbreviated))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var yearsView: some View {
        let years = HierarchicalDatePickerPlan.years(centeredOn: visibleMonth)

        return VStack(spacing: 14) {
            HStack {
                Button {
                    moveYearPage(-12)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(yearRangeText(years))
                    .font(.headline)

                Spacer()

                Button {
                    moveYearPage(12)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: yearColumns, spacing: 10) {
                ForEach(years, id: \.self) { year in
                    Button {
                        let navigation = HierarchicalDatePickerPlan.selectYear(year)
                        visibleMonth = navigation.visibleMonth
                        level = navigation.level
                    } label: {
                        Text(yearText(for: year))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    private func selectDay(_ date: Date) {
        let navigation = HierarchicalDatePickerPlan.selectDay(date)
        let selection = CalendarDateNavigationPlan.selectionResult(for: navigation.selectedDate ?? date)
        selectedDate = selection.selectedDate
        mode = selection.mode
        dismiss()
    }

    private func moveMonth(_ value: Int) {
        visibleMonth = Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func moveYearPage(_ value: Int) {
        visibleMonth = Calendar.current.date(byAdding: .year, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func yearText(for date: Date) -> String {
        String(Calendar.current.component(.year, from: date))
    }

    private func yearRangeText(_ years: [Date]) -> String {
        guard let first = years.first, let last = years.last else { return yearText(for: visibleMonth) }
        return "\(yearText(for: first)) - \(yearText(for: last))"
    }

    private func dayTextColor(day: HierarchicalMonthDay, isSelected: Bool) -> Color {
        if isSelected {
            return .white
        }
        return day.isInDisplayedMonth ? .primary : .secondary
    }
}
