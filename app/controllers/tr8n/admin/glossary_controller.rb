#--
# Copyright (c) 2010-2013 Michael Berkovich, tr8nhub.com
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

class Tr8n::Admin::GlossaryController < Tr8n::Admin::BaseController

  def index
    @terms = Tr8n::Glossary.filter(:params => params, :filter => Tr8n::GlossaryFilter)
  end
  
  def lb_update
    @glossary = Tr8n::Glossary.find_by_id(params[:id]) if params[:id]
    @glossary = Tr8n::Glossary.new unless @glossary

    if request.post?
      if @glossary.id
        @glossary.update_attributes(params[:glossary])
      else
        @glossary = Tr8n::Glossary.create(params[:glossary])
      end
      return dismiss_lightbox
    end

    render_lightbox
  end
      
end
