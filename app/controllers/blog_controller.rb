class BlogController < ApplicationController
  require 'blog_post' 
  
  def index
    files = Dir.glob('./blog_posts/*.mkd')
    @blog_posts = []
    
    files.each do |file|
      File.open(file) do |contents|
        content = contents.read
        
        title = content.split("\n\n~\n\n")[0].split("\n")[0]
        date = content.split("\n\n~\n\n")[0].split("\n")[1]
        body = content.split("\n\n~\n\n")[1]
        
        @blog_posts << BlogPost.new(title,date,body)
      end
    end
    
    @blog_posts = @blog_posts.sort_by { |blog_post| blog_post.date_parsed }
  end

end
