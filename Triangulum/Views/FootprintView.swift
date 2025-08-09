import SwiftUI
import PhotosUI

struct FootprintView: View {
    @ObservedObject var snapshotManager: SnapshotManager
    @State private var showingDeleteAlert = false
    @State private var selectedSnapshot: SensorSnapshot?
    @State private var currentPage = 0
    
    private let itemsPerPage = 10
    
    private var totalPages: Int {
        max(1, (snapshotManager.snapshots.count + itemsPerPage - 1) / itemsPerPage)
    }
    
    private var paginatedSnapshots: [SensorSnapshot] {
        let reversedSnapshots = Array(snapshotManager.snapshots.reversed())
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, reversedSnapshots.count)
        return Array(reversedSnapshots[startIndex..<endIndex])
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if snapshotManager.snapshots.isEmpty {
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
                } else {
                    VStack(spacing: 0) {
                        List {
                            ForEach(paginatedSnapshots) { snapshot in
                                SnapshotRowView(snapshot: snapshot, snapshotManager: snapshotManager)
                                    .onTapGesture {
                                        selectedSnapshot = snapshot
                                    }
                            }
                            .onDelete(perform: deleteSnapshots)
                        }
                        .listStyle(PlainListStyle())
                        
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
            }
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Sensor Footprints")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if !snapshotManager.snapshots.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear All") {
                            showingDeleteAlert = true
                        }
                        .foregroundColor(.prussianError)
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

struct SnapshotRowView: View {
    let snapshot: SensorSnapshot
    @ObservedObject var snapshotManager: SnapshotManager
    
    private var photoCount: Int {
        snapshotManager.getPhotos(for: snapshot.id).count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("📸 Snapshot")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                
                if photoCount > 0 {
                    Text("📷 \(photoCount)")
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
                    Text("Altitude")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(String(format: "%.1f m", snapshot.barometer.relativeAltitude))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.prussianBlueDark)
                }
                
                Spacer()
            }
            
            HStack {
                Text("📍")
                Text(String(format: "%.4f°, %.4f°", snapshot.location.latitude, snapshot.location.longitude))
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
                Spacer()
                Text(String(format: "±%.1f m", snapshot.location.accuracy))
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            }
        }
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

struct SnapshotDetailView: View {
    let snapshot: SensorSnapshot
    @ObservedObject var snapshotManager: SnapshotManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingDeletePhotoAlert = false
    @State private var photoToDelete: UUID?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("📷 Photos")
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
                        
                        let photos = snapshotManager.getPhotos(for: snapshot.id)
                        if photos.isEmpty {
                            Text("No photos added yet")
                                .font(.body)
                                .foregroundColor(.prussianBlueLight)
                                .italic()
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(photos) { photo in
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
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📊 Barometer Data")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.prussianBlueDark)
                        
                        DetailRowView(label: "Pressure", value: String(format: "%.2f kPa", snapshot.barometer.pressure))
                        DetailRowView(label: "Relative Altitude", value: String(format: "%.2f m", snapshot.barometer.relativeAltitude))
                        DetailRowView(label: "Sea Level Pressure", value: String(format: "%.2f kPa", snapshot.barometer.seaLevelPressure))
                        
                        if let attitude = snapshot.barometer.attitude {
                            DetailRowView(label: "Roll", value: String(format: "%.1f°", attitude.roll * 180 / .pi))
                            DetailRowView(label: "Pitch", value: String(format: "%.1f°", attitude.pitch * 180 / .pi))
                            DetailRowView(label: "Yaw", value: String(format: "%.1f°", attitude.yaw * 180 / .pi))
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📍 Location Data")
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
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("🕐 Timestamp")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.prussianBlueDark)
                        
                        Text(snapshot.timestamp, format: .dateTime.weekday().month().day().year().hour().minute().second())
                            .font(.body)
                            .foregroundColor(.prussianBlueDark)
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(12)
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
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onChange(of: selectedPhotos) { newPhotos in
            Task {
                for photoItem in newPhotos {
                    if let data = try? await photoItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            snapshotManager.addPhoto(to: snapshot.id, image: image)
                        }
                    }
                }
                await MainActor.run {
                    selectedPhotos.removeAll()
                }
            }
        }
        .alert("Delete Photo", isPresented: $showingDeletePhotoAlert) {
            Button("Cancel", role: .cancel) {
                photoToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let photoID = photoToDelete {
                    snapshotManager.removePhoto(photoID, from: snapshot.id)
                    photoToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete this photo from the snapshot.")
        }
    }
}

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
                Button(action: {
                    if currentPage > 0 {
                        currentPage -= 1
                    }
                }) {
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
                
                Button(action: {
                    if currentPage < totalPages - 1 {
                        currentPage += 1
                    }
                }) {
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