import SwiftUI
import PhotosUI

struct FootprintView: View {
    @ObservedObject var snapshotManager: SnapshotManager
    @State private var showingDeleteAlert = false
    @State private var selectedSnapshot: SensorSnapshot?
    @State private var currentPage = 0
    @State private var isCompareMode = false
    @State private var selectedForComparison: Set<UUID> = []
    @State private var showingComparison = false

    private let itemsPerPage = 10

    private var totalPages: Int {
        max(1, (snapshotManager.snapshots.count + itemsPerPage - 1) / itemsPerPage)
    }

    private var paginatedSnapshots: [SensorSnapshot] {
        let reversedSnapshots = Array(snapshotManager.snapshots.reversed())
        let startIndex = currentPage * itemsPerPage
        if startIndex >= reversedSnapshots.count {
            return []
        }
        let endIndex = min(startIndex + itemsPerPage, reversedSnapshots.count)
        return Array(reversedSnapshots[startIndex..<endIndex])
    }

    private var selectedSnapshots: [SensorSnapshot] {
        snapshotManager.snapshots.filter { selectedForComparison.contains($0.id) }
    }

    private var snapshotIDs: [UUID] {
        snapshotManager.snapshots.map(\.id)
    }

    var body: some View {
        NavigationView {
            content
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Sensor Footprints")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if !snapshotManager.snapshots.isEmpty {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        // Compare mode toggle
                        if snapshotManager.snapshots.count >= 2 {
                            Button {
                                withAnimation {
                                    isCompareMode.toggle()
                                    if !isCompareMode {
                                        selectedForComparison.removeAll()
                                    }
                                }
                            } label: {
                                Image(systemName: isCompareMode ? "xmark.circle.fill" : "arrow.left.arrow.right")
                            }
                            .foregroundColor(.white)
                        }

                        if !isCompareMode {
                            Button("Clear All") {
                                showingDeleteAlert = true
                            }
                            .foregroundColor(.prussianError)
                        }
                    }
                }
            }
            .alert("Clear All Snapshots", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    snapshotManager.clearAllSnapshots()
                    currentPage = 0
                }
            } message: {
                Text("This will permanently delete all your sensor snapshots. This action cannot be undone.")
            }
            .sheet(item: $selectedSnapshot) { snapshot in
                SnapshotDetailView(snapshot: snapshot, snapshotManager: snapshotManager)
            }
            .onChange(of: snapshotIDs) { _, ids in
                let validIDs = Set(ids)
                selectedForComparison = selectedForComparison.intersection(validIDs)
            }
            .sheet(isPresented: $showingComparison) {
                comparisonSheet
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack {
            if snapshotManager.snapshots.isEmpty {
                emptyState
            } else {
                snapshotList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.prussianBlueLight)

            Text("No Snapshots Yet")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.prussianBlueDark)

            Text("Take your first snapshot from the main screen to see your sensor footprints here")
                .font(.body)
                .foregroundColor(.prussianBlueLight)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snapshotList: some View {
        VStack(spacing: 0) {
            if isCompareMode {
                compareModeHeader
            }

            snapshotListView

            if totalPages > 1 {
                PaginationView(
                    currentPage: $currentPage,
                    totalPages: totalPages,
                    totalItems: snapshotManager.snapshots.count,
                    itemsPerPage: itemsPerPage
                )
                .padding()
                .background(Color.prussianSoft)
            }
        }
    }

    private var snapshotListView: some View {
        List {
            ForEach(paginatedSnapshots) { snapshot in
                SnapshotRowView(
                    snapshot: snapshot,
                    snapshotManager: snapshotManager,
                    isCompareMode: isCompareMode,
                    isSelected: selectedForComparison.contains(snapshot.id)
                )
                .onTapGesture {
                    handleSnapshotTap(snapshot)
                }
            }
            .onDelete { offsets in
                guard !isCompareMode else { return }
                deleteSnapshots(offsets: offsets)
            }
        }
        .listStyle(PlainListStyle())
    }

    @ViewBuilder
    private var comparisonSheet: some View {
        if selectedSnapshots.count == 2 {
            SnapshotComparisonView(
                snapshot1: selectedSnapshots[0],
                snapshot2: selectedSnapshots[1]
            )
            .onAppear {
                // Dismiss sheet if snapshots are removed while presented
                if selectedSnapshots.count != 2 {
                    showingComparison = false
                }
            }
        } else {
            // Fallback view when snapshots are unavailable
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.prussianWarning)

                Text("Comparison Unavailable")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)

                Text("One or both selected snapshots have been removed")
                    .font(.body)
                    .foregroundColor(.prussianBlueLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .onAppear {
                // Auto-dismiss the sheet
                showingComparison = false
            }
        }
    }

    // MARK: - Compare Mode Header

    private var compareModeHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Select 2 snapshots to compare")
                    .font(.subheadline)
                    .foregroundColor(.prussianBlueDark)

                Spacer()

                Text("\(selectedSnapshots.count)/2 selected")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.prussianBlueLight.opacity(0.2))
                    .cornerRadius(8)
            }

            if selectedSnapshots.count == 2 {
                Button {
                    showingComparison = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Compare Selected")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.prussianBlue)
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.9))
    }

    // MARK: - Selection Logic

    private func toggleSelection(_ snapshot: SensorSnapshot) {
        if selectedForComparison.contains(snapshot.id) {
            selectedForComparison.remove(snapshot.id)
        } else if selectedForComparison.count < 2 {
            selectedForComparison.insert(snapshot.id)
        }
    }

    private func handleSnapshotTap(_ snapshot: SensorSnapshot) {
        if isCompareMode {
            toggleSelection(snapshot)
        } else {
            selectedSnapshot = snapshot
        }
    }

    private func deleteSnapshots(offsets: IndexSet) {
        for index in offsets {
            let snapshotToDelete = paginatedSnapshots[index]
            if let originalIndex = snapshotManager.snapshots.firstIndex(where: { $0.id == snapshotToDelete.id }) {
                snapshotManager.deleteSnapshot(at: originalIndex)
            }
        }

        // Adjust current page if needed
        if currentPage >= totalPages {
            currentPage = max(0, totalPages - 1)
        }
    }
}

// MARK: - Snapshot Row View

struct SnapshotRowView: View {
    let snapshot: SensorSnapshot
    @ObservedObject var snapshotManager: SnapshotManager
    var isCompareMode: Bool = false
    var isSelected: Bool = false

    private var photoCount: Int {
        snapshot.photoIDs.count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator in compare mode
            if isCompareMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .prussianAccent : .prussianBlueLight)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Snapshot")
                        .font(.headline)
                        .foregroundColor(.prussianBlueDark)

                    if photoCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "photo")
                            Text("\(photoCount)")
                        }
                        .font(.caption)
                        .foregroundColor(.prussianBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.prussianBlueLight.opacity(0.2))
                        .cornerRadius(8)
                    }

                    Spacer()
                    Text(snapshot.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pressure")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text(String(format: "%.2f kPa", snapshot.barometer.pressure))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.prussianBlueDark)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("GPS Altitude")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text(String(format: "%.1f m", snapshot.location.altitude))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.prussianBlueDark)
                    }

                    Spacer()
                }

                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundColor(.prussianBlueLight)
                    Text(String(format: "%.4f°, %.4f°", snapshot.location.latitude, snapshot.location.longitude))
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Spacer()
                    Text(String(format: "±%.1f m", snapshot.location.accuracy))
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.prussianAccent.opacity(0.1) : Color.white.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.prussianAccent : Color.clear, lineWidth: 2)
                )
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Snapshot Detail View

struct SnapshotDetailView: View {
    let snapshot: SensorSnapshot
    @ObservedObject var snapshotManager: SnapshotManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingDeletePhotoAlert = false
    @State private var photoToDelete: UUID?
    /// In-memory snapshot of photos for this view; populated asynchronously
    /// via prewarmCache so disk I/O never blocks the main thread.
    @State private var loadedPhotos: [SnapshotPhoto] = []

    private var seaLevelPressureText: String {
        guard let seaLevelPressure = snapshot.barometer.seaLevelPressure else {
            return "--"
        }
        return String(format: "%.2f kPa", seaLevelPressure)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    photoSection
                    barometerSection
                    locationSection
                    timestampSection
                }
                .padding()
            }
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Snapshot Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .onChange(of: selectedPhotos) { _, newPhotos in
            Task {
                for photoItem in newPhotos {
                    if let data = try? await photoItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run { _ = snapshotManager.addPhoto(to: snapshot.id, image: image) }
                    }
                }
                await MainActor.run { selectedPhotos.removeAll() }
            }
        }
        .alert("Delete Photo", isPresented: $showingDeletePhotoAlert) {
            Button("Cancel", role: .cancel) { photoToDelete = nil }
            Button("Delete", role: .destructive) {
                if let photoID = photoToDelete {
                    snapshotManager.removePhoto(photoID, from: snapshot.id)
                    photoToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete this photo from the snapshot.")
        }
        .task(id: snapshot.id) {
            await snapshotManager.prewarmCache(for: snapshot.id)
            loadedPhotos = snapshotManager.getPhotos(for: snapshot.id)
        }
        .onChange(of: snapshotManager.snapshots.first(where: { $0.id == snapshot.id })?.photoIDs.count ?? 0) { _, _ in
            loadedPhotos = snapshotManager.getPhotos(for: snapshot.id)
        }
    }

    @ViewBuilder private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.prussianBlue)
                }
            }
            if loadedPhotos.isEmpty {
                Text("No photos added yet")
                    .font(.body)
                    .foregroundColor(.prussianBlueLight)
                    .italic()
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(loadedPhotos) { photo in
                        if let image = photo.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                                .onLongPressGesture {
                                    photoToDelete = photo.id
                                    showingDeletePhotoAlert = true
                                }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
    }

    @ViewBuilder private var barometerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Barometer Data")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.prussianBlueDark)
            DetailRowView(label: "Pressure", value: String(format: "%.2f kPa", snapshot.barometer.pressure))
            DetailRowView(label: "Sea Level Pressure", value: seaLevelPressureText)
            if let attitude = snapshot.barometer.attitude {
                DetailRowView(label: "Roll", value: String(format: "%.1f°", attitude.roll * 180 / .pi))
                DetailRowView(label: "Pitch", value: String(format: "%.1f°", attitude.pitch * 180 / .pi))
                DetailRowView(label: "Yaw", value: String(format: "%.1f°", attitude.yaw * 180 / .pi))
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
    }

    @ViewBuilder private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location Data")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.prussianBlueDark)
            DetailRowView(label: "Latitude", value: String(format: "%.6f°", snapshot.location.latitude))
            DetailRowView(label: "Longitude", value: String(format: "%.6f°", snapshot.location.longitude))
            DetailRowView(label: "GPS Altitude", value: String(format: "%.2f m", snapshot.location.altitude))
            DetailRowView(label: "Accuracy", value: String(format: "±%.2f m", snapshot.location.accuracy))
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
    }

    @ViewBuilder private var timestampSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timestamp")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.prussianBlueDark)
            Text(snapshot.timestamp,
                 format: .dateTime.weekday().month().day().year().hour().minute().second())
                .font(.body)
                .foregroundColor(.prussianBlueDark)
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
    }
}

// MARK: - Pagination View

struct PaginationView: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let totalItems: Int
    let itemsPerPage: Int

    private var startItem: Int {
        currentPage * itemsPerPage + 1
    }

    private var endItem: Int {
        min((currentPage + 1) * itemsPerPage, totalItems)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Showing \(startItem)-\(endItem) of \(totalItems) snapshots")
                .font(.caption)
                .foregroundColor(.prussianBlueLight)

            HStack(spacing: 20) {
                Button {
                    if currentPage > 0 {
                        currentPage -= 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .font(.body)
                    .foregroundColor(currentPage > 0 ? .prussianBlue : .prussianBlueLight)
                }
                .disabled(currentPage == 0)

                Text("Page \(currentPage + 1) of \(totalPages)")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.prussianBlueDark)

                Button {
                    if currentPage < totalPages - 1 {
                        currentPage += 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.body)
                    .foregroundColor(currentPage < totalPages - 1 ? .prussianBlue : .prussianBlueLight)
                }
                .disabled(currentPage >= totalPages - 1)
            }
        }
    }
}

// MARK: - Detail Row View

struct DetailRowView: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.prussianBlueLight)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.prussianBlueDark)
        }
    }
}

#Preview {
    let manager = SnapshotManager()
    return FootprintView(snapshotManager: manager)
}
