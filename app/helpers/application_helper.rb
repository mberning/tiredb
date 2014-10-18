module ApplicationHelper
  def link(label, url)
    unless url.blank?
      link_to label, url
    else
      ''
    end
  end
end
