module Api::V1
  class NotificationsController < ApiController
    # GET /v1/notifications?page=1
    def index
      page = [params[:page].to_i, 1].max
      offset = (page - 1) * Notification::PAGE_SIZE

      notifications = current_user.notifications
        .newest_first
        .limit(Notification::PAGE_SIZE + 1)  # fetch one extra to detect next page
        .offset(offset)

      has_more = notifications.size > Notification::PAGE_SIZE
      notifications = notifications.first(Notification::PAGE_SIZE)

      render json: {
        data: notifications.map(&:as_inbox_json),
        meta: { has_more: has_more, page: page }
      }
    end

    # GET /v1/notifications/unread_count
    #
    # API contract (Phase 3 frontend builds against this):
    #   Response: { "unread_count": N, "outstanding_count": N }
    #   where N = count of notifications with resolved_at IS NULL for current_user
    #   (same value for both keys in v1).
    #
    # The badge count derives from outstanding obligations (unresolved), NOT from
    # read state. `unread_count` keeps the same value so stale clients that only
    # read that key silently inherit the outstanding-count semantic. The
    # read/read_all endpoints remain seen-state-only affordances.
    def unread_count
      count = current_user.notifications.unresolved.count
      render json: { unread_count: count, outstanding_count: count }
    end

    # PATCH /v1/notifications/:id/read
    def read
      notification = current_user.notifications.find_by(id: params[:id])
      return head :not_found unless notification

      notification.mark_read!
      head :ok
    end

    # PATCH /v1/notifications/read_all
    def read_all
      current_user.notifications.unread.update_all(read: true, read_at: Time.current)
      head :ok
    end
  end
end
