# encoding: UTF-8
require 'i18nliner/pre_processors/erb_pre_processor'
require 'i18nliner/errors'

describe I18nliner::PreProcessors::ErbPreProcessor do
  before do
    I18nliner::PreProcessors::ErbPreProcessor::TBlock.any_instance.stub(:infer_key).and_return(:key)
  end

  describe ".process" do
    def process(string)
      I18nliner::PreProcessors::ErbPreProcessor.process(string)
    end

    it "should transform t block expressions" do
      process("<%= t do %>hello world!<% end %>").should ==
        '<%= t :key, "hello world!" %>'
    end

    it "should remove extraneous whitespace" do
      process("<%= t do %> ohai!\n lulz\t <% end %>").should ==
        '<%= t :key, "ohai! lulz" %>'
    end

    it "should not translate other block expressions" do
      process(<<-SOURCE).
        <%= form_for do %>
          <%= t do %>Your Name<% end %>
          <input>
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= form_for do %>
          <%= t :key, "Your Name" %>
          <input>
        <% end %>
        EXPECTED
    end

    it "should reject malformed erb" do
      expect { process("<%= t do %>") }.
        to raise_error(I18nliner::MalformedErbError)
    end

    it "should disallow nesting non-t block expressions in a t block expression" do
      expect { process("<%= t { %><%= s { %>nope<% } %><% } %>") }.
        to raise_error(I18nliner::TBlockNestingError)
      expect { process("<%= t { %><%= s(:some, :args) { |args, here, too| %>nope<% } %><% } %>") }.
        to raise_error(I18nliner::TBlockNestingError)
    end

    it "should disallow statements in a t block expression" do
      expect { process("<%= t { %>I am <% if happy %>happy<% else %>sad<% end %><% } %>") }.
        to raise_error(I18nliner::TBlockNestingError)
    end

    it "should create wrappers for markup" do
      process(<<-SOURCE).
        <%= t do %>
          <b>bold</b>, or even <a href="#"><i><img>combos</i></a> get wrapper'd
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "*bold*, or even **combos** get wrapper'd", :wrappers => ["<b>\\\\1</b>", "<a href=\\\"#\\\"><i><img>\\\\1</i></a>"] %>
        EXPECTED
    end

    it "should not create wrappers for markup with multiple text nodes" do
      expect { puts process("<%= t do %>this is <b><i>too</i> complicated</b><% end %>") }.
        to raise_error(I18nliner::UnwrappableContentError)
    end

    it "should create wrappers for link_to calls with string content" do
      process(<<-SOURCE).
        <%= t do %>
          You should <%= link_to("create a profile", "/profile") %>.
          idk why <%= link_to "this " + "link", "/zomg" %> has concatention
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "You should *create a profile*. idk why **this link** has concatention", :wrappers => [link_to("\\\\1", "/profile"), link_to("\\\\1", "/zomg")] %>
        EXPECTED
    end

    it "should create wrappers for link_to calls with other content" do
      process(<<-SOURCE).
        <%= t do %>
          Your account rep is <%= link_to(@user.name, "/user/\#{@user.id}") %>
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "Your account rep is *%{user_name}*", :user_name => (@user.name), :wrappers => [link_to("\\\\1", "/user/\#{@user.id}")] %>
        EXPECTED
    end

    it "should reuse identical wrappers" do
      process(<<-SOURCE).
        <%= t do %>
          the wrappers for
          <%= link_to "these", url %> <%= link_to "links", url %> are the same,
          as are the ones for
          <b>these</b> <b>tags</b>
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "the wrappers for **these** **links** are the same, as are the ones for *these* *tags*", :wrappers => ["<b>\\\\1</b>", link_to("\\\\1", url)] %>
        EXPECTED
    end

    it "should generate placeholders for inline expressions" do
      process(<<-SOURCE).
        <%= t do %>
          Hello, <%= name %>
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "Hello, %{name}", :name => (name) %>
        EXPECTED
    end

    it "should generate placeholders for inline expressions in wrappers" do
      process(<<-SOURCE).
        <%= t do %>
          Go to <a href="/asdf" title="<%= name %>">your account</a>
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "Go to *your account*", :wrappers => ["<a href=\\"/asdf\\" title=\\"\#{name}\\">\\\\1</a>"] %>
        EXPECTED
    end

    # this is really the same as the one above, but it's good to have a
    # spec for this in case the underlying implementation changes
    # dramatically
    it "should transform nested t block expressions in wrappers" do
      process(<<-SOURCE).
        <%= t do %>
          Go to <a href="/asdf" title="<%= t do %>manage account stuffs, <%= name %><% end %>">your account</a>
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "Go to *your account*", :wrappers => ["<a href=\\"/asdf\\" title=\\"\#{t :key, \"manage account stuffs, %{name}\", :name => (name)}\\">\\\\1</a>"] %>
        EXPECTED
    end

    it "should generate placeholders for empty markup" do
      process(<<-SOURCE).
        <%= t do %>
          Create <input name="count"> groups
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "Create %{input_name_count} groups", :input_name_count => ("<input name=\\"count\\">".html_safe) %>
        EXPECTED
    end

    it "should unescape entities" do
      process(<<-SOURCE).
        <%= t do %>
          &copy; <%= year %> ACME Corp. All Rights Reserved. Our lawyers &gt; your lawyers
        <% end %>
        SOURCE
      should == <<-EXPECTED
        <%= t :key, "© %{year} ACME Corp. All Rights Reserved. Our lawyers > your lawyers", :year => (year) %>
        EXPECTED
    end
  end
end
