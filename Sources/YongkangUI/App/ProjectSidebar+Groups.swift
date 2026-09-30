import SwiftUI
import YongkangCore

/// Groups in the sidebar. A group is a name its projects carry rather than a box holding them
/// (`ProjectGroups`), so what the list draws as one group is the run of neighbours naming it —
/// which is why everything here is asked of an index rather than of a group object. It also means
/// an empty group cannot exist: one is started from a project, and it goes when its last project
/// leaves it.
extension ProjectSidebar {
    /// Where the insertion line is while a project is dragged. The index alone will not do: the
    /// gap above a group's header and the gap above its first project are the same height and the
    /// same index, and differ only in the level they land in.
    struct Insertion: Equatable {
        let index: Int
        let group: String?
    }

    /// How far a group's contents sit in from a loose project. The same step again carries a
    /// project's own rows, so the column reads three levels deep at its deepest.
    static var groupIndent: CGFloat { 14 }

    func startsRun(at index: Int) -> Bool {
        projects[index].group != nil && (index == 0 || projects[index - 1].group != projects[index].group)
    }

    func endsRun(at index: Int) -> Bool {
        projects[index].group != nil
            && (index == projects.count - 1 || projects[index + 1].group != projects[index].group)
    }

    /// A project inside a folded group is not drawn; nothing else folds this way.
    func folded(_ item: SidebarProject) -> Bool {
        item.group.map { foldedGroups.contains($0) } ?? false
    }

    /// The header over a run. It opens nothing — a group is not a place, it is how the list is
    /// arranged — so it never takes the selection, and its name is dimmer than a project's to say
    /// so. Folded, it wears the counts of everything it hides, because work waiting on you must
    /// not be foldable out of sight; open, it wears none, since its projects show their own.
    func groupHeader(_ group: String, at index: Int) -> some View {
        let shut = foldedGroups.contains(group)
        let members = projects[index...].prefix { $0.group == group }
        return Button {
            if shut { foldedGroups.remove(group) } else { foldedGroups.insert(group) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: shut ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tx3)
                    .frame(width: 12)
                Text(group).font(Typography.body(.semibold)).foregroundStyle(Theme.tx2).lineLimit(1)
                Text("\(members.count)").font(Typography.monoCaption).foregroundStyle(Theme.tx4)
                Spacer(minLength: 4)
                if shut {
                    let needsYou = members.reduce(0) { $0 + $1.needsYou }
                    let toReview = members.reduce(0) { $0 + $1.toReview }
                    if needsYou > 0 { count(needsYou, Theme.amber, dot: true) }
                    if toReview > 0 { count(toReview, Theme.green, dot: false) }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .accessibilityLabel("\(group), \(members.count) project\(members.count == 1 ? "" : "s")")
        // At the top level: dropping here puts a project above the whole group, not into it.
        .dropTarget(before: index, into: nil, line: $insertion, move: move)
        .contextMenu {
            Button("Rename Group…") { renameGroup(group) }
            Button("Ungroup") { ungroup(group) }
        }
    }

    /// The gap after a run's last project, so a project can be dragged to the end of a group
    /// rather than only above one of its members. The twin of `endGap`, one level in.
    func groupEndGap(_ group: String, before index: Int) -> some View {
        Color.clear.frame(height: 14)
            .contentShape(Rectangle())
            .groupRule(true)
            .dropTarget(before: index, into: group, line: $insertion, move: move)
    }
}

extension View {
    /// A row's place in the list: indented again when its project is inside a group, and carrying
    /// that group's rule. `top` is the gap above it — 8 over a project, 1 over one of its rows.
    func groupIndented(_ item: SidebarProject, top: CGFloat) -> some View {
        padding(.leading, item.group == nil ? 8 : 8 + ProjectSidebar.groupIndent)
            .padding(.trailing, 8)
            .padding(.top, top)
            .groupRule(item.group != nil)
    }

    /// The 1pt rule down the left of everything in a group. Each row draws its own segment, over
    /// the gap above it as well as its own height, so the segments meet into one line. It is what
    /// makes the indent read as containment rather than as a second kind of row — and it is why a
    /// group needs no folder icon, which would only argue with a project being a folder itself.
    func groupRule(_ inGroup: Bool) -> some View {
        overlay(alignment: .leading) {
            Rectangle().fill(Theme.line2)
                .frame(width: 1)
                .padding(.leading, 21)
                .opacity(inGroup ? 1 : 0)
        }
    }

    /// Makes the gap above this row a place a dragged project lands: the insertion line while a
    /// drag is over it, and the move when it is dropped. Only the line moves — a row never lights
    /// up, because a project highlighted under the cursor reads as somewhere to drop the drag
    /// *into*, and nothing here goes inside a project.
    ///
    /// The line starts at the indent of the level it lands in, which is the whole of how "into
    /// this group" is told from "between the groups": the two gaps sit at the same height, and
    /// only where the line begins says which one the drop takes.
    func dropTarget(
        before index: Int, into group: String?, line: Binding<ProjectSidebar.Insertion?>,
        move: @escaping (Project.ID, Int, String?) -> Void
    ) -> some View {
        let here = ProjectSidebar.Insertion(index: index, group: group)
        return overlay(alignment: .top) {
            Rectangle().fill(Theme.accent)
                .frame(height: 2)
                .padding(.leading, group == nil ? 8 : 8 + ProjectSidebar.groupIndent)
                .padding(.trailing, 8)
                .offset(y: 3)
                .opacity(line.wrappedValue == here ? 1 : 0)
        }
        .dropDestination(for: String.self) { dropped, _ in
            line.wrappedValue = nil
            guard let dragged = dropped.first.flatMap(UUID.init(uuidString:)) else { return false }
            move(dragged, index, group)
            return true
        } isTargeted: { over in
            if over {
                line.wrappedValue = here
            } else if line.wrappedValue == here {
                line.wrappedValue = nil
            }
        }
    }
}
