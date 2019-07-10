# == License
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2011 Brice Texier, Thibaud Merigon
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

module Backend
  class NotificationsController < Backend::BaseController
    def index
      @unread_notifications = current_user.unread_notifications.order(created_at: :desc)
      if params[:mode] == :unread
        new_notifications_count = @unread_notifications.where('created_at >= ?', Time.now - params[:ago].to_f).count
        global_count = @unread_notifications.count
        unread_notifs = @unread_notifications.map { |notif| { message: notif.human_message,
                                                              created_at: notif.created_at,
                                                              url: backend_notification_path(notif),
                                                              icon: "icon-#{NotificationsHelper::LEVEL_ICONS[notif.level.to_sym]}" } }
        response = {
          total_count: global_count,
          new_entries_count: new_notifications_count,
          unread_notifs: unread_notifs
        }
        render json: response.to_json
      else
        @notifications = Notification.order(created_at: :desc)
      end
    end

    def show
      notification = find_and_check
      return unless notification
      notification.read!
      if notification.target_url
        redirect_to notification.target_url
      elsif notification.target
        target = notification.target
        redirect_to(controller: target.class.model_name.plural, action: :show, id: target.id)
      else
        redirect_to action: :index
      end
    end

    def destroy
      if params[:id]
        notification = find_and_check
        return unless notification
        notification.read!
      else
        current_user.unread_notifications.find_each(&:read!)
      end
      redirect_to params[:redirect] || { action: :index }
    end
  end
end
