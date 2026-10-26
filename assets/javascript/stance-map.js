// Renders the US states map for /initiatives/stance-on-science/map.
//
// Requires d3 v7 and topojson-client v3 already loaded on the page, plus the
// window globals:
//   window.STANCE_ACTIVE_STATES — array of two-letter USPS codes (lowercase)
//   window.STANCE_STATES_URL    — base URL for per-state pages (e.g.
//                                 "/initiatives/stance-on-science/states/")

(function () {
  "use strict";

  // us-atlas keys features by FIPS code. This maps FIPS -> USPS for the 50
  // states + DC. DC is included so it can render but is not currently used
  // for navigation.
  var FIPS_TO_USPS = {
    "01": "AL", "02": "AK", "04": "AZ", "05": "AR", "06": "CA", "08": "CO",
    "09": "CT", "10": "DE", "11": "DC", "12": "FL", "13": "GA", "15": "HI",
    "16": "ID", "17": "IL", "18": "IN", "19": "IA", "20": "KS", "21": "KY",
    "22": "LA", "23": "ME", "24": "MD", "25": "MA", "26": "MI", "27": "MN",
    "28": "MS", "29": "MO", "30": "MT", "31": "NE", "32": "NV", "33": "NH",
    "34": "NJ", "35": "NM", "36": "NY", "37": "NC", "38": "ND", "39": "OH",
    "40": "OK", "41": "OR", "42": "PA", "44": "RI", "45": "SC", "46": "SD",
    "47": "TN", "48": "TX", "49": "UT", "50": "VT", "51": "VA", "53": "WA",
    "54": "WV", "55": "WI", "56": "WY"
  };

  var STATE_NAMES = {
    AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas",
    CA: "California", CO: "Colorado", CT: "Connecticut", DE: "Delaware",
    DC: "District of Columbia", FL: "Florida", GA: "Georgia", HI: "Hawaii",
    ID: "Idaho", IL: "Illinois", IN: "Indiana", IA: "Iowa", KS: "Kansas",
    KY: "Kentucky", LA: "Louisiana", ME: "Maine", MD: "Maryland",
    MA: "Massachusetts", MI: "Michigan", MN: "Minnesota", MS: "Mississippi",
    MO: "Missouri", MT: "Montana", NE: "Nebraska", NV: "Nevada",
    NH: "New Hampshire", NJ: "New Jersey", NM: "New Mexico", NY: "New York",
    NC: "North Carolina", ND: "North Dakota", OH: "Ohio", OK: "Oklahoma",
    OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island", SC: "South Carolina",
    SD: "South Dakota", TN: "Tennessee", TX: "Texas", UT: "Utah",
    VT: "Vermont", VA: "Virginia", WA: "Washington", WV: "West Virginia",
    WI: "Wisconsin", WY: "Wyoming"
  };

  var TOPOJSON_URL = "https://cdn.jsdelivr.net/npm/us-atlas@3/states-10m.json";

  function init() {
    var container = document.getElementById("stance-map-canvas");
    if (!container || typeof d3 === "undefined" || typeof topojson === "undefined") {
      return;
    }

    var active = new Set((window.STANCE_ACTIVE_STATES || []).map(function (s) {
      return s.toUpperCase();
    }));
    var statesBaseUrl = window.STANCE_STATES_URL || "/initiatives/stance-on-science/states/";

    var width = 975;
    var height = 610;

    var svg = d3.select(container).append("svg")
      .attr("viewBox", "0 0 " + width + " " + height)
      .attr("width", "100%")
      .attr("preserveAspectRatio", "xMidYMid meet")
      .attr("class", "stance-map__svg")
      .attr("role", "img")
      .style("display", "block")
      .style("max-width", "100%")
      .style("height", "auto");

    // us-atlas v3 ships unprojected (lat/lng) coordinates, so we apply
    // d3.geoAlbersUsa() at the scale/translate that matches our 975x610
    // viewBox. The official D3 examples use these exact values.
    var projection = d3.geoAlbersUsa()
      .scale(1300)
      .translate([487.5, 305]);
    var path = d3.geoPath(projection);

    d3.json(TOPOJSON_URL).then(function (us) {
      var states = topojson.feature(us, us.objects.states).features;

      svg.append("g")
        .attr("class", "stance-map__states")
        .selectAll("path")
        .data(states)
        .join("path")
          .attr("d", path)
          .attr("class", function (d) {
            var usps = FIPS_TO_USPS[String(d.id).padStart(2, "0")];
            return usps && active.has(usps) ? "stance-map__state stance-map__state--active" : "stance-map__state";
          })
          .attr("data-usps", function (d) {
            return FIPS_TO_USPS[String(d.id).padStart(2, "0")] || "";
          })
          .attr("tabindex", function (d) {
            var usps = FIPS_TO_USPS[String(d.id).padStart(2, "0")];
            return usps && active.has(usps) ? 0 : -1;
          })
          .attr("role", function (d) {
            var usps = FIPS_TO_USPS[String(d.id).padStart(2, "0")];
            return usps && active.has(usps) ? "link" : "presentation";
          })
          .on("click", onActivate)
          .on("keydown", function (event) {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              onActivate.call(this, event);
            }
          })
        .append("title")
          .text(function (d) {
            var usps = FIPS_TO_USPS[String(d.id).padStart(2, "0")];
            var name = STATE_NAMES[usps] || "";
            if (usps && active.has(usps)) {
              return name + " — view responses";
            }
            return name + " — no responses yet";
          });

      // Draw the interior state borders on top so neighboring active states
      // share a clean 1px black seam regardless of fill.
      svg.append("path")
        .attr("class", "stance-map__borders")
        .attr("d", path(topojson.mesh(us, us.objects.states, function (a, b) { return a !== b; })))
        .attr("fill", "none")
        .attr("stroke", "#000")
        .attr("stroke-width", 0.5)
        .attr("stroke-linejoin", "round");

      function onActivate() {
        var usps = this.getAttribute("data-usps");
        if (!usps || !active.has(usps)) return;
        var dest = statesBaseUrl;
        if (dest.charAt(dest.length - 1) !== "/") dest += "/";
        window.location.href = dest + usps.toLowerCase();
      }
    }).catch(function (err) {
      container.innerHTML = '<p><em>Could not load the map. Please try again later, or use the search page.</em></p>';
      // eslint-disable-next-line no-console
      console.error("stance-map: failed to load topojson", err);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
}());
