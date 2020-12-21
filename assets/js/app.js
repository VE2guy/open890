// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import "../css/app.scss"

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import deps with the dep name or local files with a relative path, for example:
//
import { Socket } from "phoenix"
import socket from "./socket"
import "phoenix_html"
import LiveSocket from "phoenix_live_view"

import ControlHooks from "./control_hooks"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: ControlHooks,
  params: {_csrf_token: csrfToken},
  metadata: {
    click: (evt, el) => {
      // var e = evt.target;
      // var dim = e.getBoundingClientRect();
      // console.log("dim", dim);

      // var x = evt.clientX - dim.left;
      // var y = evt.clientY - dim.top;
      // console.log("coords:", {x:x, y:y})

      // This is all specific to the bandscope SVG click,
      // NOT all click events going to phoenix

      let svg = document.querySelector('svg#bandScope');
      let pt = svg.createSVGPoint();

      pt.x = evt.clientX;
      pt.y = evt.clientY;

      var cursorPt = pt.matrixTransform(svg.getScreenCTM().inverse());

      return {
        x: cursorPt.x,
        y: cursorPt.y
      }
    }
  }
})
liveSocket.connect()


let audioStreamChannel = socket.channel("radio:audio_stream", {})
audioStreamChannel.join()
  .receive("ok", resp => { console.log("Joined audio STREAM successfully", resp) })
  .receive("error", resp => { console.log("Unable to join", resp) })

let audioCount = 0

audioStreamChannel.on("audio_data", (data) => {
  let buffer = []
  let decoded = atob(data.payload)

  for (var i = 0; i < decoded.length; i++) {
    buffer.push(decoded.charCodeAt(i))
  }
  
  audioCount += 1

  if (audioCount % 500 == 0) {
    console.log("Received", audioCount, "audio packets")
    console.log("buffer", buffer);
  }
})


window.testFunc = function(msg) {
  console.log("testFunc:", msg);
}