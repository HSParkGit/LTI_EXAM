Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # LTI 1.3 Routes
  # GET/POST /lti/login - OIDC Login Initiation (Canvas에서 호출, 일부 Canvas 버전은 POST 사용)
  # POST /lti/launch - LTI Launch (Canvas에서 id_token 전송)
  namespace :lti do
    match "login", to: "login#initiate", via: [:get, :post]
    post "launch", to: "launch#handle"
  end

  # Projects Routes
  resources :projects, only: [:index, :show, :new, :create, :edit, :update, :destroy]

  # Admin Routes (LTI Platform 관리)
  namespace :admin do
    resources :lti_platforms
  end

  # Defines the root path route ("/")
  # 루트는 Admin 페이지 (LTI Platform 관리)
  # Projects는 LTI Launch 후에만 접근 가능
  root "admin/lti_platforms#index"
end
