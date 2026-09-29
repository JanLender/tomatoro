import Foundation

/// A registered project a task can be filed under. Stored separately from
/// tasks so the same project can be referenced — and renamed — from many
/// tasks at once.
struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// Loads and persists the list of registered projects, and which one is the
/// default, as a JSON file in Application Support alongside `tasks.json`.
///
/// File location: `~/Library/Application Support/Tomatoro/projects.json`
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    /// The project newly created tasks are assigned to automatically.
    @Published private(set) var defaultProjectID: Project.ID?

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Tomatoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("projects.json")
        load()
    }

    var defaultProject: Project? {
        project(withID: defaultProjectID)
    }

    func project(withID id: Project.ID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: - Mutations

    /// Adds a new project and persists the change. The very first project
    /// registered becomes the default automatically, since there's
    /// otherwise no default to fall back to.
    @discardableResult
    func addProject(named name: String) -> Project {
        let project = Project(name: name)
        projects.append(project)
        if defaultProjectID == nil {
            defaultProjectID = project.id
        }
        save()
        return project
    }

    /// Renames a project and persists the change. This only updates the
    /// registry — cascading the new name onto tasks/records that reference
    /// it is the caller's job (see `TaskStore.refreshProjectName(for:newName:)`).
    func rename(_ project: Project, to name: String) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].name = name
        save()
    }

    /// Marks a project as the one newly created tasks default to.
    func setDefault(_ project: Project) {
        guard defaultProjectID != project.id else { return }
        defaultProjectID = project.id
        save()
    }

    /// Removes a project from the registry and persists the change. This
    /// only updates the registry — clearing it from tasks/records that
    /// reference it is the caller's job (see `TaskStore.clearProject(_:)`).
    /// If the deleted project was the default, the next remaining one (if
    /// any) becomes the default.
    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if defaultProjectID == project.id {
            defaultProjectID = projects.first?.id
        }
        save()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var projects: [Project]
        var defaultProjectID: Project.ID?
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            projects = decoded.projects
            defaultProjectID = decoded.defaultProjectID
        }
    }

    private func save() {
        let snapshot = Snapshot(projects: projects, defaultProjectID: defaultProjectID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
