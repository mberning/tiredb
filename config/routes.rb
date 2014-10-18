Tiresearch::Application.routes.draw do
  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action
  match 'standard_search' => 'search#standard_search', :as => 'standard_search'
  match 'wheel_search' => 'search#wheel_search', :as => 'wheel_search'
  match 'staggered_search' => 'search#staggered_search', :as => 'staggered_search'
  match 'hardcore_search' => 'search#hardcore_search', :as => 'hardcore_search'
  
  match 'standard_search_form' => 'search#standard_search_form', :as => 'standard_search_form'
  match 'wheel_search_form' => 'search#wheel_search_form', :as => 'wheel_search_form'
  match 'staggered_search_form' => 'search#staggered_search_form', :as => 'staggered_search_form'
  match 'hardcore_search_form' => 'search#hardcore_search_form', :as => 'hardcore_search_form'
  
  match 'blog' => 'blog#index', :as => 'blog'
  
  namespace :admin do
    match 'tire_stats' => 'tires#stats'
  end

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
   root :to => "search#index"

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id(.:format)))'
end
