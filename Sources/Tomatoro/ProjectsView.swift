import SwiftUI

/// Its own movable, resizable window for maintaining the list of registered
/// projects tasks can be filed under — add, rename, delete, and pick which
/// one is the default for newly created tasks.
struct ProjectsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var projectStore: ProjectStore

    @State private var newProjectName = ""
    @State private var renamingProject: Project?
    @State private var projectPendingDeletion: Project?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if projectStore.projects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "folder",
                    description: Text("Add one below — it becomes the default automatically.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(projectStore.projects) { project in
                        HStack {
                            Text(project.name)
                            if project.id == projectStore.defaultProjectID {
                                Spacer()
                                Text("Default")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Rename") {
                                renamingProject = project
                            }
                            if project.id != projectStore.defaultProjectID {
                                Button("Set as Default") {
                                    projectStore.setDefault(project)
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                projectPendingDeletion = project
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                TextField("New project…", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addProject)
                Button(action: addProject) {
                    Image(systemName: "plus")
                }
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty || newProjectNameTaken)
            }
            .padding(8)

            if newProjectNameTaken {
                Text("A project with this name already exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 320, idealWidth: 360, minHeight: 320, idealHeight: 420)
        .sheet(item: $renamingProject) { project in
            RenameProjectSheet(
                name: project.name,
                isTaken: { projectStore.isNameTaken($0, excluding: project.id) }
            ) { newName in
                projectStore.rename(project, to: newName)
            }
        }
        .alert(
            "Delete this project?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { isPresented in if !isPresented { projectPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let projectPendingDeletion {
                    store.clearProject(projectPendingDeletion.id)
                    projectStore.deleteProject(projectPendingDeletion)
                }
            }
        } message: {
            Text("Tasks filed under this project become unassigned. This can't be undone.")
        }
    }

    /// Projects are addressed by name in the scripting API, so names must
    /// stay unique (ignoring case).
    private var newProjectNameTaken: Bool {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && projectStore.isNameTaken(name)
    }

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !newProjectNameTaken else { return }
        projectStore.addProject(named: name)
        newProjectName = ""
    }
}

/// A small sheet for renaming a project — same pattern as `RenameTaskSheet`.
private struct RenameProjectSheet: View {
    let isTaken: (String) -> Bool
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(name: String, isTaken: @escaping (String) -> Bool, onSave: @escaping (String) -> Void) {
        self.isTaken = isTaken
        self.onSave = onSave
        self._name = State(initialValue: name)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameTaken: Bool { !trimmedName.isEmpty && isTaken(trimmedName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename project")
                .font(.headline)

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            if nameTaken {
                Text("A project with this name already exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || nameTaken)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func save() {
        guard !trimmedName.isEmpty, !nameTaken else { return }
        onSave(trimmedName)
        dismiss()
    }
}
