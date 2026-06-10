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
    def unread_count
      count = current_user.notifications.unread.count
      render json: { unread_count: count }
    end

    # PATCH /v1/notifications/:id/read
    def read
      # Scoped to current_user.notifications, so another user's notification
      # resolves to nil → an explicit 404 (rather than relying on the implicit
      # ActiveRecord::RecordNotFound→404 rescue, which is not active in the
      # test env where show_exceptions is off).
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
