module Admin
  class TracksController < BaseController
    before_action :set_track, only: [ :show, :edit, :update, :destroy ]

    def index
      @tracks = Track.includes(:album, :artist).order(:title)
    end

    def show
    end

    def edit
    end

    def update
      if @track.update(track_params)
        redirect_to admin_tracks_path, notice: "Track was successfully updated."
      else
        render :edit
      end
    end

    def destroy
      @track.destroy
      redirect_to admin_tracks_path, notice: "Track was successfully deleted."
    end

    private

    def set_track
      @track = Track.find(params[:id])
    end

    def track_params
      params.require(:track).permit(:title, :spotify_id, :explicit)
    end
  end
end
