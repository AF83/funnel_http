defmodule FunnelHttpTest do
  use ExUnit.Case
  use Plug.Test

  @opts FunnelHttp.Router.init([])

  setup do
    on_exit fn ->
      Funnel.Es.destroy("funnel")
    end
  end

  def headers do
    [
      {"content-type", "application/json"}
    ]
  end

  def authenticate_headers(token \\ "default_token") do
    [
      {"content-type", "application/json"},
      {"authorization", token}
    ]
  end

  test "404" do
    conn = conn(:post, "/ohai")
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 404
    assert conn.assigns[:token] == nil
    assert response["error"] == "Not found"
  end

  test "status" do
    conn = conn(:get, "/status")
    conn = FunnelHttp.Router.call(conn, @opts)
    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.assigns[:token] == nil
    assert response["status"] == 200
  end

  test "returns a token in json" do
    conn = conn(:post, "/register")
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 201
    assert response["token"] != nil
  end

  test "does not allow to create a query without token" do
    query = '{"query" : {"match" : {"message" : "elasticsearch"}}}' |> IO.iodata_to_binary
    conn = conn(:post, "/queries", query, headers: headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 400
    assert response["token"] == nil
    assert response["error"] == "Unauthenticated"
  end

  test "does not allow to create a query without `query` and `metadata` keys" do
    query = '{"query" : {"match" : {"message" : "elasticsearch"}}}' |> IO.iodata_to_binary
    conn = conn(:post, "/queries", query, headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 422
    assert response["token"] == nil
    assert response["error"] == "`query` and `metadata` keys must be present."
  end

  test "allow to create a query with token, and settings forwarding" do
    query = '{"query":{"query" : {"match" : {"message" : "elasticsearch"}}}, "metadata":{"name":"Query Creation"}}' |> IO.iodata_to_binary
    conn = conn(:post, "/queries", query, headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 201
    assert response["query_id"] != nil
    assert response["token"] == nil
    assert response["metadata"]["name"] == "Query Creation"

    Funnel.Es.destroy("queries")
  end

  test "does not allow to update a query without token" do
    query = '{"query" : {"match" : {"message" : "elasticsearch"}}}' |> IO.iodata_to_binary
    conn = conn(:put, "/queries/:query_id", query, headers: headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 400
    assert response["token"] == nil
    assert response["error"] == "Unauthenticated"
  end

  test "allow to update a query with token" do
    query = '{"query":{"query" : {"match" : {"message" : "elasticsearch"}}}, "metadata":{"name":"Query Update"}}' |> IO.iodata_to_binary
    conn = conn(:post, "/queries", query, headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)
    {:ok, response} = Poison.decode(conn.resp_body)
    query_id = response["query_id"]

    query = '{"query":{"query" : {"match" : {"message" : "update"}}}, "metadata":{"name":"Query Update 2"}}' |> IO.iodata_to_binary
    conn = conn(:put, "/queries/#{query_id}", query, headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)
    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 200
    assert response["query_id"] == query_id
    assert response["metadata"]["name"] == "Query Update 2"
    assert response["token"] == nil

    Funnel.Es.destroy("queries")
  end

  test "does not allow to destroy a query without token" do
    query = '{"query" : {"match" : {"message" : "elasticsearch"}}}' |> IO.iodata_to_binary
    conn = conn(:delete, "/queries/:query_id", query, headers: headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 400
    assert response["token"] == nil
    assert response["error"] == "Unauthenticated"
  end

  test "allow to destroy a query with token" do
    query = '{"query":{"query" : {"match" : {"message" : "update"}}}, "metadata":{"name":"Query Update 2"}}' |> IO.iodata_to_binary
    conn = conn(:post, "/queries", query, headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)
    {:ok, response} = Poison.decode(conn.resp_body)
    query_id = response["query_id"]

    conn = conn(:delete, "/queries/#{query_id}", [], headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)
    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 200
    assert response["token"] == nil
    assert FunnelHttp.Query.Registry.find(query_id) == {:not_found, query_id, nil}

    Funnel.Es.destroy("queries")
  end

  test "submit a document to the percolator" do
    message = "{\"doc\":{\"message\":\"this new elasticsearch percolator feature is nice, borat style\"}}"
    conn = conn(:post, "/feeding", message, headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 204
  end

  test "submit a list of documents to the percolator" do
    messages = "[{\"doc\" : {\"message\":\"So long, and thanks for all the fish\"}},{\"doc\":{\"message\":\"Say thanks to the fish\"}}]"
    conn = conn(:post, "/feeding", messages, headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 204
  end

  test "river without a token" do
    conn = conn(:get, "/river", [], headers: headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 400
    assert response["token"] == nil
    assert response["error"] == "Unauthenticated"
  end

  test "river with a token" do
    conn = conn(:get, "/river", "", headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    assert conn.status == 200
    assert conn.state == :chunked
  end

  test "river with a token and send a message" do
    conn = conn(:get, "/river", "", headers: authenticate_headers("river"))
    conn = FunnelHttp.Router.call(conn, @opts)

    assert conn.status == 200
    assert conn.state == :chunked

    message = "{\"doc\":{\"message\":\"this new elasticsearch percolator feature is nice, borat style\"}}"
    response = %{query_ids: [], body: message}
    Funnel.Transistor.notify("river", Funnel.Uuid.generate, response)
  end

  test "find queries without a token" do
    conn = conn(:get, "/queries", "", headers: headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 400
    assert response["token"] == nil
    assert response["error"] == "Unauthenticated"
  end

  test "find queries with a token, but without any results" do
    conn = conn(:get, "/queries", "", headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert conn.state == :sent
    assert conn.status == 200
    assert Enum.count(response) == 0
  end

  test "find queries based on token" do
    query = '{"query" : {"term" : {"field1" : "value1"}}}' |> IO.iodata_to_binary
    token = "query_find"
    {_status, response} = Funnel.Es.register("funnel", token, query)
    {:ok, body} = Poison.decode response
    query_id =  body["query_id"]
    metadata = %{"name" => "Plop"}
    FunnelHttp.Query.Registry.insert(query_id, metadata)
    Funnel.Es.refresh

    conn = conn(:get, "/queries?token=#{token}", "", headers: authenticate_headers)
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)
    query = List.first(response)

    assert Enum.count(response) == 1
    assert query["query_id"] == query_id
    assert query["metadata"] == metadata
    assert conn.state == :sent
    assert conn.status == 200
  end

  test "find queries based on token on several indexes" do
    query = '{"query" : {"term" : {"field1" : "value1"}}}' |> IO.iodata_to_binary
    token = "query_find"
    {_status, response} = Funnel.Es.register("several_indexes", token, query)
    {:ok, body} = Poison.decode response
    query_id =  body["query_id"]
    metadata = %{"name" => "Plop"}
    FunnelHttp.Query.Registry.insert(query_id, metadata)
    {_status, response} = Funnel.Es.register("funnel", token, query)
    {:ok, body} = Poison.decode response
    query_id =  body["query_id"]
    metadata = %{"name" => "Plop"}
    FunnelHttp.Query.Registry.insert(query_id, metadata)
    Funnel.Es.refresh

    conn = conn(:get, "/queries", "", headers: authenticate_headers(token))
    conn = FunnelHttp.Router.call(conn, @opts)

    {:ok, response} = Poison.decode(conn.resp_body)

    assert Enum.count(response) == 2
    assert conn.state == :sent
    assert conn.status == 200
    Funnel.Es.destroy("several_indexes")
  end
end
