# encoding: utf-8

require "test/unit"

require "couch-shell/plugin"

class TestPluginInfo < Test::Unit::TestCase

  def test_class_name_to_plugin_name
    assert_equal "core",
      CouchShell::PluginInfo.class_name_to_plugin_name("CouchShell::CorePlugin")
    assert_equal "core",
      CouchShell::PluginInfo.class_name_to_plugin_name("CouchShell::Core")
    assert_equal "core",
      CouchShell::PluginInfo.class_name_to_plugin_name("Core")
    assert_equal "http",
      CouchShell::PluginInfo.class_name_to_plugin_name("HTTP")
    assert_equal "http",
      CouchShell::PluginInfo.class_name_to_plugin_name("Foo::HTTP")
    assert_equal "http_client",
      CouchShell::PluginInfo.class_name_to_plugin_name("Foo::HttpClient")
    assert_equal "http_client",
      CouchShell::PluginInfo.class_name_to_plugin_name("Foo::HTTPClient")
    assert_equal "http_c",
      CouchShell::PluginInfo.class_name_to_plugin_name("HttpC")
    assert_equal "h_client",
      CouchShell::PluginInfo.class_name_to_plugin_name("HClient")
    assert_equal "http11_client",
      CouchShell::PluginInfo.class_name_to_plugin_name("Http11Client")
    assert_equal "http11_client",
      CouchShell::PluginInfo.class_name_to_plugin_name("HTTP11Client")
    assert_equal "test0",
      CouchShell::PluginInfo.class_name_to_plugin_name("Test0")
    assert_equal "http_client",
      CouchShell::PluginInfo.class_name_to_plugin_name("Http_Client")
  end

end
