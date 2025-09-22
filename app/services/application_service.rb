class ApplicationService
  class << self
    def call(**args, &block)
      new(**args).call(&block)
    end
  end
end
