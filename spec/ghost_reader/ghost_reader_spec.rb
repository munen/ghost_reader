require 'spec_helper'

describe "Ghost Reader" do
  before(:all) do
#    I18n.locale=:en
    fallback = I18n::Backend::Simple.new
    fallback.store_translations(:en, {:notfound=>'Not found'})
    fallback.store_translations(:de, {:notfound=>'Nicht gefunden'})
    # Short Wait-Time for Testing
    I18n.backend=GhostReader::Backend.new("http://localhost:35623/",
                                          :default_backend=>fallback,
                                          :wait_time=>1)
    # Initializes a Handler
    @handler=GhostHandler.new
    # Start a Mongrel-Server for Testing Ghost Reader
    @server = Mongrel::HttpServer.new('0.0.0.0', 35623)
    @server.register('/', @handler)
    @server.run

  end
  after(:all) do
    # Shutdown the Mongrel-Server
    @server.stop
  end
  it('can translate the key "test"') do
    I18n.t('test').should == "hello1"
  end

  it('Cache miss not returns the fallback') {
    I18n.t('notfound').should == "translation missing: en.notfound"
  }

  it('first call should not set if-modified-since') do
    @handler.last_params["HTTP_IF_MODIFIED_SINCE"].should == nil
  end

  it('can translate the key "test" with a update-post') do
    sleep 2
    I18n.t('test').should == "hello2"
  end

  it('hit recorded') do
    @handler.last_hits.should == {'test'=>1}
  end

  it('cache-miss with fallback-values') do
    @handler.last_miss.should == {"notfound"=>{
            "default"=>{
                    "de"=>"Nicht gefunden",
                    "en"=>"Not found"},
            "count"=>{
                    "en"=>1}}}
  end

  it('if-modified-since is set') do
    @handler.last_params["HTTP_IF_MODIFIED_SINCE"].should_not == nil
  end
  it('can translate the key "test" with a update-post') do
    @handler.not_modified=true
    sleep 2
    I18n.t('test').should == "hello2"
  end
end