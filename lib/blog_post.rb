class BlogPost
  require 'kramdown'
  
  attr_accessor :title, :date, :body 
  
  def initialize(title, date, body)
    @title = title
    @date = date
    @body = body
  end
  
  def body_html
    doc = Kramdown::Document.new(@body)
    return doc.to_html
  end
  
  def date_parsed
    Date.parse(@date)
  end
  
  def date_formatted
    date_parsed.strftime("%D")
  end
end