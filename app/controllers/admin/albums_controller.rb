module Admin
  class AlbumsController < BaseController
    before_action :set_album, only: [ :show, :edit, :update, :destroy ]

    def index
      @albums = Album.includes(:artist).order(:name)
    end

    def show
    end

    def edit
    end

    def update
      if @album.update(album_params)
        redirect_to admin_albums_path, notice: "Album was successfully updated."
      else
        render :edit
      end
    end

    def destroy
      @album.destroy
      redirect_to admin_albums_path, notice: "Album was successfully deleted."
    end

    private

    def set_album
      @album = Album.find(params[:id])
    end

    def album_params
      params.require(:album).permit(:name, :release_date, :album_type)
    end
  end
end
