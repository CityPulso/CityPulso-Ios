import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 我标记的地点（Android `PlaceRequestsViewModel`）：按状态分页；撤回待审核的。 */
@MainActor
@Observable
final class PlaceRequestsModel {
    var status = PlaceRequestStatus.pending {
        didSet { if status != oldValue { rows = places.pageMine(status) } }
    }

    private(set) var rows: PagedList<PlaceRequest, Int>
    /** 正在撤回的那条。 */
    private(set) var busyId: String?

    @ObservationIgnored @Injected(\.placeRequestService) private var places
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init() {
        rows = Container.shared.placeRequestService().pageMine(.pending)
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func withdraw(_ requestId: String) async {
        busyId = requestId
        defer { busyId = nil }
        do {
            try await places.cancel(requestId)
            PulsoMessageCenter.shared.success("place_withdrawn")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "place_withdraw_failed")
        }
    }
}

/** 我标记的地点（Android `PlaceRequestsScreen`，WEB `/panel/account/places`）：状态分段，每个地点一张卡，撤回 / 重新提交 / 打开。 */
struct PlaceRequestsView: View {
    @State private var model = PlaceRequestsModel()
    @State private var withdrawing: PlaceRequest?

    var body: some View {
        List {
            Section {
                Picker(selection: $model.status) {
                    ForEach(PlaceRequestStatus.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if model.rows.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = model.rows.error {
                PulsoLoadErrorView(error) { Task { await model.rows.refresh() } }
                    .listRowBackground(Color.clear)
            } else if model.rows.isEmpty {
                empty.listRowBackground(Color.clear)
            } else {
                ForEach(model.rows.items, id: \.id) { row in
                    PlaceRow(row: row, imageURL: model.imageURL(row.imageIds.first), busy: model.busyId == row.id) {
                        withdrawing = row
                    }
                    .onAppear { if row.id == model.rows.items.last?.id { model.rows.loadMore() } }
                }
            }
        }
        .navigationTitle("place_requests_title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: NearRoute.markPlace(latitude: nil, longitude: nil)) {
                    Label("place_mark_action", systemImage: "mappin.and.ellipse")
                }
            }
        }
        .refreshable { await model.rows.refresh() }
        .task(id: model.status) { await model.rows.observe() }
        .sheet(item: $withdrawing) { row in
            // Android `holdConfirm`：按住确认。
            VStack(alignment: .leading, spacing: 16) {
                Text("place_withdraw_title").font(.title3.bold())
                Text(verbatim: localizedFormat("place_withdraw_body", row.proposedName ?? "")).foregroundStyle(.secondary)
                PulsoHoldButton("place_withdraw", loading: model.busyId == row.id) {
                    Task {
                        await model.withdraw(row.id)
                        withdrawing = nil
                    }
                }
            }
            .padding(24)
            .presentationDetents([.height(240)])
        }
    }

    @ViewBuilder
    private var empty: some View {
        ContentUnavailableView {
            Text(emptyTitle)
        } description: {
            model.status == .pending ? Text(verbatim: localizedFormat("place_empty_pending_hint", placeRequestsPendingMax)) : Text(emptyBody)
        } actions: {
            if model.status == .pending {
                NavigationLink(value: NearRoute.markPlace(latitude: nil, longitude: nil)) { Text("place_mark_action") }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch model.status {
        case .pending: "place_empty_pending"
        case .approved: "place_empty_approved"
        case .rejected: "place_empty_rejected"
        case .cancelled: "place_empty_cancelled"
        }
    }

    private var emptyBody: LocalizedStringKey {
        switch model.status {
        case .pending: "place_empty_pending_hint"
        case .approved: "place_empty_approved_hint"
        case .rejected: "place_empty_rejected_hint"
        case .cancelled: "place_empty_cancelled_hint"
        }
    }
}

/** 一个地点：封面、名字、类型和状态、地址，被拒时的审核意见，以及按状态的操作。 */
private struct PlaceRow: View {
    let row: PlaceRequest
    let imageURL: URL?
    let busy: Bool
    let onWithdraw: () -> Void

    var body: some View {
        let status = PlaceRequestStatus.fromWire(row.status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Color(.tertiarySystemFill)
                    if let imageURL {
                        PulsoRemoteImage(url: imageURL)
                    } else {
                        Image(systemName: BuildingTypeVisual.of(row.proposedBuildingType).systemImage).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: row.proposedName ?? "").font(.headline).lineLimit(2)
                    HStack(spacing: 6) {
                        if let type = row.proposedBuildingType {
                            Text(BuildingType.fromWire(type).labelKey).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: .capsule)
                        }
                        Text(status.labelKey).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    if let address = row.proposedAddress, !address.isEmpty {
                        Text(verbatim: address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            if status == .rejected, let note = row.reviewNote, !note.isEmpty {
                Text(verbatim: localizedFormat("place_review_note", note)).font(.footnote)
            }
            switch status {
            case .pending:
                Button(action: onWithdraw) {
                    if busy { ProgressView() } else { Text("place_withdraw") }
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(busy)
            case .rejected:
                NavigationLink(value: NearRoute.resubmitPlace(requestId: row.id)) { Text("place_resubmit") }
                    .buttonStyle(.bordered)
            case .approved:
                if let buildingId = row.buildingId {
                    NavigationLink(value: NearRoute.building(buildingId: buildingId)) { Text("place_open") }
                        .buttonStyle(.bordered)
                }
            case .cancelled:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}

extension PlaceRequest: Identifiable {}
