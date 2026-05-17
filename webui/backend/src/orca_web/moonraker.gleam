//// Pushes a sliced G-code file to a Klipper printer via the Moonraker HTTP API.
////
////   POST {base_url}/server/files/upload   (multipart, field "file", root=gcodes)
////   POST {base_url}/printer/print/start?filename=...   (optional auto-start)

import gleam/bit_array
import gleam/http
import gleam/http/request.{type Request}
import gleam/httpc
import gleam/int
import gleam/result
import gleam/string
import simplifile

pub type SendRequest {
  SendRequest(
    base_url: String,
    api_key: String,
    gcode_path: String,
    filename: String,
    start_print: Bool,
  )
}

pub type SendError {
  ReadError(String)
  RequestError(String)
  UploadRejected(status: Int, body: String)
}

const boundary = "----orcawebboundary7MA4YWxkTrZu0gW"

/// Pure: assemble the multipart/form-data body. Unit tested directly.
pub fn multipart_body(filename: String, file: BitArray) -> BitArray {
  let dashes = "--" <> boundary
  let header =
    dashes
    <> "\r\nContent-Disposition: form-data; name=\"root\"\r\n\r\ngcodes\r\n"
    <> dashes
    <> "\r\nContent-Disposition: form-data; name=\"file\"; filename=\""
    <> filename
    <> "\"\r\nContent-Type: application/octet-stream\r\n\r\n"
  let footer = "\r\n" <> dashes <> "--\r\n"
  bit_array.concat([
    bit_array.from_string(header),
    file,
    bit_array.from_string(footer),
  ])
}

fn base_request(
  base_url: String,
  api_key: String,
) -> Result(Request(String), SendError) {
  request.to(base_url)
  |> result.map_error(fn(_) { RequestError("invalid base url: " <> base_url) })
  |> result.map(fn(req) {
    case api_key {
      "" -> req
      key -> request.set_header(req, "x-api-key", key)
    }
  })
}

fn upload(send: SendRequest) -> Result(Nil, SendError) {
  use file <- result.try(
    simplifile.read_bits(send.gcode_path)
    |> result.map_error(fn(e) { ReadError(simplifile.describe_error(e)) }),
  )
  use base <- result.try(base_request(send.base_url, send.api_key))

  let req =
    base
    |> request.set_method(http.Post)
    |> request.set_path("/server/files/upload")
    |> request.set_header(
      "content-type",
      "multipart/form-data; boundary=" <> boundary,
    )
    |> request.set_body(multipart_body(send.filename, file))

  case httpc.send_bits(req) {
    Error(_) -> Error(RequestError("upload request failed"))
    Ok(resp) ->
      case resp.status >= 200 && resp.status < 300 {
        True -> Ok(Nil)
        False ->
          Error(UploadRejected(
            resp.status,
            bit_array.to_string(resp.body) |> result.unwrap(""),
          ))
      }
  }
}

fn start(send: SendRequest) -> Result(Nil, SendError) {
  use base <- result.try(base_request(send.base_url, send.api_key))
  let req =
    base
    |> request.set_method(http.Post)
    |> request.set_path("/printer/print/start")
    |> request.set_query([#("filename", send.filename)])
    |> request.set_body("")

  case httpc.send(req) {
    Error(_) -> Error(RequestError("print start request failed"))
    Ok(resp) ->
      case resp.status >= 200 && resp.status < 300 {
        True -> Ok(Nil)
        False -> Error(UploadRejected(resp.status, resp.body))
      }
  }
}

pub fn send(req: SendRequest) -> Result(String, SendError) {
  use _ <- result.try(upload(req))
  case req.start_print {
    False -> Ok("uploaded " <> req.filename)
    True ->
      start(req)
      |> result.map(fn(_) { "uploaded and started print: " <> req.filename })
  }
}

/// Render an error for the JSON response.
pub fn describe(err: SendError) -> String {
  case err {
    ReadError(m) -> "could not read g-code: " <> m
    RequestError(m) -> m
    UploadRejected(status, body) ->
      "printer rejected upload (HTTP "
      <> int.to_string(status)
      <> "): "
      <> string.slice(body, 0, 300)
  }
}
