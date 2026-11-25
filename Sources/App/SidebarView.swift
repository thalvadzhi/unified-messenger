import SwiftUI

/// Source list with one row per service and an unread badge.
struct SidebarView: View {
    let model: AppModel

    private var selection: Binding<ServiceID?> {
        Binding(
            get: { model.selected },
            set: { if let id = $0 { model.selected = id } }
        )
    }

    var body: some View {
        List(selection: selection) {
            ForEach(Service.all) { service in
                HStack {
                    Label(service.name, systemImage: service.symbolName)
                    Spacer()
                    if let count = model.unread[service.id], count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                    }
                }
                .tag(service.id)
            }
        }
        .listStyle(.sidebar)
    }
}
