//
//  ContentView.swift
//  podbubble
//
//  Created by Nate Schaffner on 3/11/25.
//

import SwiftUI

// MARK: - Models
struct Podcast: Identifiable {
    let id = UUID()
    let name: String
    var hosts: [Host]
}

struct Host: Identifiable {
    let id = UUID()
    let name: String
    var podcasts: [Podcast]
}

// MARK: - Link Struct
struct Link: Identifiable {
    let id = UUID()
    let from: UUID
    let to: UUID
}

// MARK: - GraphModel with Animated Layout
class GraphModel: ObservableObject {
    @Published var nodes: [Node] = []
    @Published var links: [Link] = []
    @Published var isProcessing = false  // Show progress

    struct Node: Identifiable {
        let id: UUID
        var position: CGPoint
        let label: String
        let color: Color
        var isDragging: Bool = false
    }

    private let screenBounds = CGSize(width: 400, height: 700)
    private let iterations = 200
    private let repulsionStrength: CGFloat = 4000
    private let attractionStrength: CGFloat = 0.05
    private let minDistance: CGFloat = 80

    init() {
        loadInitialData()
        applyForceDirectedLayout(animated: true)
    }

    // Load pre-set podcasts and hosts
    private func loadInitialData() {
        let initialData: [[String: Any]] = [
            ["pod": "TGG", "hosts": ["Ben", "Adam"]],
            ["pod": "FF", "hosts": ["Ben", "Adam", "Rod"]],
            ["pod": "RodLine", "hosts": ["Rod", "Merlin"]],
            ["pod": "FST", "hosts": ["Don", "Chap", "Rod", "Casey"]],
            ["pod": "DBF", "hosts": ["Don", "Merlin", "John"]],
            ["pod": "RD", "hosts": ["John", "Merlin"]],
            ["pod": "ATP", "hosts": ["Marco", "Casey", "John"]]
        ]

        var hostMap: [String: Node] = [:]

        Task {
            for entry in initialData {
                guard let podcastName = entry["pod"] as? String,
                      let hostNames = entry["hosts"] as? [String] else { continue }
                
                let podcastNode = Node(id: UUID(),
                                       position: randomStartPosition(),
                                       label: podcastName,
                                       color: .blue)
                await MainActor.run{
                    withAnimation{
                        nodes.append(podcastNode)
                    }
                }
                
                
                for hostName in hostNames {
                    if hostMap[hostName] == nil {
                        let hostNode = Node(id: UUID(),
                                            position: randomStartPosition(),
                                            label: hostName,
                                            color: .red)
                        await MainActor.run{
                            withAnimation{
                                nodes.append(hostNode)
                            }
                        }
                        
                        hostMap[hostName] = hostNode
                    }
                    await MainActor.run{
                        withAnimation {
                            links.append(Link(from: podcastNode.id, to: hostMap[hostName]!.id))
                        }
                    }
                    
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                //            Task{
                //                applyForceDirectedLayout(animated: true)
                //
                //            }
            }
            applyForceDirectedLayout(animated: true)
        }
    }

    // Generate random initial positions
    private func randomStartPosition() -> CGPoint {
        return CGPoint(x: CGFloat.random(in: 100...300), y: CGFloat.random(in: 200...600))
    }

    // Add a new podcast with hosts
    func addPodcast(name: String, hostNames: [String]) {
        let podcastNode = Node(id: UUID(),
                               position: randomStartPosition(),
                               label: name,
                               color: .blue)
        nodes.append(podcastNode)

        var hostMap: [String: Node] = [:]
        for hostName in hostNames {
            if let existingHost = nodes.first(where: { $0.label == hostName && $0.color == .red }) {
                hostMap[hostName] = existingHost
            } else {
                let hostNode = Node(id: UUID(),
                                    position: randomStartPosition(),
                                    label: hostName,
                                    color: .red)
                nodes.append(hostNode)
                hostMap[hostName] = hostNode
            }
            links.append(Link(from: podcastNode.id, to: hostMap[hostName]!.id))
        }

        applyForceDirectedLayout(animated: true)
    }

    
    // Apply force-directed layout **progressively**
    func applyForceDirectedLayout(animated: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.isProcessing = true

            for _ in 0..<self.iterations {
                var newPositions: [UUID: CGPoint] = [:]

                for i in self.nodes.indices {
                    if self.nodes[i].isDragging { continue } // Skip dragged nodes

                    var forceX: CGFloat = 0
                    var forceY: CGFloat = 0

                    // Repulsion between nodes (spreading effect)
                    for j in self.nodes.indices where i != j {
                        let dx = self.nodes[i].position.x - self.nodes[j].position.x
                        let dy = self.nodes[i].position.y - self.nodes[j].position.y
                        let distance = max(sqrt(dx * dx + dy * dy), 1)

                        if distance < self.minDistance {
                            let repulsion = self.repulsionStrength / (distance * distance)
                            forceX += repulsion * (dx / distance)
                            forceY += repulsion * (dy / distance)
                        }
                    }

                    // Attraction forces (connected nodes pull together)
                    for link in self.links {
                        if link.from == self.nodes[i].id || link.to == self.nodes[i].id {
                            let neighborID = (link.from == self.nodes[i].id) ? link.to : link.from
                            if let neighborIndex = self.nodes.firstIndex(where: { $0.id == neighborID }) {
                                let dx = self.nodes[neighborIndex].position.x - self.nodes[i].position.x
                                let dy = self.nodes[neighborIndex].position.y - self.nodes[i].position.y
                                let distance = max(sqrt(dx * dx + dy * dy), 1)

                                let attraction = self.attractionStrength * distance
                                forceX += attraction * (dx / distance)
                                forceY += attraction * (dy / distance)
                            }
                        }
                    }

                    var newX = self.nodes[i].position.x + forceX
                    var newY = self.nodes[i].position.y + forceY

                    newX = min(max(newX, 50), self.screenBounds.width - 50)
                    newY = min(max(newY, 100), self.screenBounds.height - 50)

                    newPositions[self.nodes[i].id] = CGPoint(x: newX, y: newY)
                }

                DispatchQueue.main.async {
                    for i in self.nodes.indices {
                        if let newPosition = newPositions[self.nodes[i].id] {
                            self.nodes[i].position = newPosition
                        }
                    }
                }
                usleep(20000) // Delay to show progressive movement
            }

            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
}

// MARK: - Graph View
struct ForceDirectedGraphView: View {
    @ObservedObject var model: GraphModel

    var body: some View {
        ZStack {
            ForEach(model.links) { link in
                if let fromNode = model.nodes.first(where: { $0.id == link.from }),
                   let toNode = model.nodes.first(where: { $0.id == link.to }) {
                    LineView(from: fromNode.position, to: toNode.position)
                        .stroke(Color.gray, lineWidth: 1)
                }
            }

            ForEach(model.nodes) { node in
                FloatingNode(size: 40, color: node.color, label: node.label, position: node.position) { newPosition in
                    if let index = model.nodes.firstIndex(where: { $0.id == node.id }) {
                        model.nodes[index].position = newPosition
                        model.nodes[index].isDragging = true
                    }
                }
            }
        }
    }
}

// MARK: - Floating Node
struct FloatingNode: View {
    let size: CGFloat
    let color: Color
    let label: String
    let position: CGPoint
    var onDrag: (CGPoint) -> Void

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Text(label).foregroundColor(.white).font(.caption))
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        onDrag(value.location)
                    }
            )
    }
}

// MARK: - Line View
struct LineView: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

// MARK: - Add Podcast View
struct AddPodcastView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var podcastName: String = ""
    @State private var hosts: String = ""
    var model: GraphModel

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Podcast Details")) {
                    TextField("Podcast Name", text: $podcastName)
                    TextField("Hosts (comma separated)", text: $hosts)
                }
                Section {
                    Button("Add Podcast") {
                        let hostNames = hosts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        model.addPodcast(name: podcastName, hostNames: hostNames)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .navigationTitle("Add Podcast")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}


// MARK: - Main View
struct ContentView: View {
    @StateObject var model = GraphModel()
    @State private var showAddPodcastView = false
    
    var body: some View {
        NavigationView {
            VStack {
                if model.isProcessing {
                    ProgressView("Optimizing Layout...")
                        .padding()
                }

                ZStack {
                    ForceDirectedGraphView(model: model)
                }
                .padding()

                HStack {
                    Button("Reset View") {
                        model.applyForceDirectedLayout(animated: true)
                    }
                    .padding()
                    
                    Button("Add Podcast") {
                        showAddPodcastView.toggle()
                    }
                    .padding()
                    .sheet(isPresented: $showAddPodcastView){
                        AddPodcastView(model: model)
                    }
                }
            }
            .navigationTitle("Podcast Graph")
        }
    }
}
