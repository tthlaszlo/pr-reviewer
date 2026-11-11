import SwiftUI
import BuddyCore

struct PullReviewsView: View {
    @ObservedObject var workspace: Workspace
    let pull: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { workspace.closeReviews() } label: {
                Label("My pull requests", systemImage: "chevron.left")
            }.buttonStyle(.plain).foregroundStyle(Focus.accentText)
                .accessibilityIdentifier("back-to-my-prs")
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pull.title).font(Focus.font(26, weight: .semibold))
                        .textSelection(.enabled).accessibilityAddTraits(.isHeader)
                    Text("\(pull.repository)  #\(pull.number)")
                        .font(Focus.font(12)).foregroundStyle(Focus.muted)
                }
                Spacer(minLength: 0)
                Link("Open on GitHub", destination: pull.url)
                    .foregroundStyle(Focus.accentText)
                Button {
                    workspace.openReviews(pull)
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(FocusButtonStyle()).disabled(workspace.reviewsLoading)
                    .accessibilityIdentifier("refresh-reviews")
            }
            Rectangle().fill(Focus.border).frame(height: 1)
            Text("Reviews").font(Focus.font(17, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if workspace.reviewsLoading {
                ProgressView("Loading reviews…").frame(maxWidth: .infinity).padding(.vertical, 32)
            } else if let error = workspace.reviewsError {
                VStack(alignment: .leading, spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Focus.warning)
                    Button("Try again") { workspace.openReviews(pull) }
                        .buttonStyle(FocusButtonStyle()).accessibilityIdentifier("retry-reviews")
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Focus.warningSurface).clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let history = workspace.reviewHistory {
                if history.partial {
                    Label("Review history is incomplete. Open this PR on GitHub to see the full history.", systemImage: "exclamationmark.triangle")
                        .font(Focus.font(12)).foregroundStyle(Focus.warning)
                        .padding(12).background(Focus.warningSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if history.reviews.isEmpty && !history.partial {
                            Text("No reviews yet").font(Focus.font(17, weight: .medium)).padding(.vertical, 24)
                        }
                        ForEach(history.reviews) { review in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(review.reviewer).font(Focus.font(14, weight: .semibold))
                                    Text(review.status).font(Focus.font(12, weight: .medium))
                                        .foregroundStyle(review.state == "APPROVED" ? Focus.success : Focus.muted)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Focus.sidebar).clipShape(RoundedRectangle(cornerRadius: 5))
                                    Spacer()
                                    if let date = review.submittedAt { timestamp(date) }
                                }
                                if let body = review.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(body).textSelection(.enabled)
                                } else {
                                    Text("No summary provided.").foregroundStyle(Focus.muted)
                                }
                            }.padding(.vertical, 16)
                            Rectangle().fill(Focus.border).frame(height: 1)
                        }
                        if !history.comments.isEmpty {
                            Text("Code comments").font(Focus.font(17, weight: .semibold))
                                .accessibilityAddTraits(.isHeader).padding(.top, 24).padding(.bottom, 8)
                            ForEach(history.comments) { comment in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(comment.author).font(Focus.font(14, weight: .semibold))
                                        Spacer()
                                        timestamp(comment.createdAt)
                                    }
                                    Text(comment.location).font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Focus.muted).textSelection(.enabled)
                                    Text(comment.body).textSelection(.enabled)
                                }.padding(.vertical, 16)
                                Rectangle().fill(Focus.border).frame(height: 1)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("review-history")
            }
            Spacer(minLength: 0)
        }.font(Focus.font(14)).padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func timestamp(_ date: Date) -> some View {
        Text(date.formatted(date: .abbreviated, time: .shortened))
            .font(Focus.font(12)).foregroundStyle(Focus.muted)
    }
}
