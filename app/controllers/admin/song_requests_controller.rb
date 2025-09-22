module Admin
  class SongRequestsController < BaseController
    before_action :set_song_request, only: [ :show, :edit, :update, :destroy, :approve, :reject ]

    def index
      @song_requests = SongRequest.includes(:track, :request_queue)
                                 .order(created_at: :desc)

      @song_requests = @song_requests.where(status: params[:status]) if params[:status].present?
    end

    def show
    end

    def edit
    end

    def update
      if @song_request.update(song_request_params)
        redirect_to admin_song_requests_path, notice: "Song request was successfully updated."
      else
        render :edit
      end
    end

    def destroy
      @song_request.destroy
      redirect_to admin_song_requests_path, notice: "Song request was successfully deleted."
    end

    def approve
      @song_request.update(status: "queued")
      redirect_to admin_song_requests_path, notice: "Song request approved and queued."
    end

    def reject
      @song_request.update(status: "failed")
      redirect_to admin_song_requests_path, alert: "Song request rejected."
    end

    def clear_queue
      SongRequest.active.update_all(status: "failed")
      redirect_to admin_song_requests_path, notice: "Queue cleared."
    end

    private

    def set_song_request
      @song_request = SongRequest.find(params[:id])
    end

    def song_request_params
      params.require(:song_request).permit(:status, :position)
    end
  end
end
