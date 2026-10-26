// Adapted from stance-map.js: reuse its state identifiers, D3 projection,
// TopoJSON geometry, and responsive SVG approach for the visits overview.
// Requires d3 v7 and topojson-client v3, loaded with defer before this script.
(function () {
  "use strict";

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

  var container = document.getElementById("district-visit-map-canvas");
  if (!container || typeof d3 === "undefined" || typeof topojson === "undefined") return;

  var visitedStates = new Set(container.dataset.states.toUpperCase().split(","));
  var geometryUrl = "https://cdn.jsdelivr.net/npm/us-atlas@3/states-10m.json";
  // Small states need callouts so every abbreviation remains distinguishable.
  // Anchors sit inside their states; destinations reserve space beside the map.
  var callouts = {
    VT: { anchor: [-72.7, 44.0], label: [822, 42] },
    NH: { anchor: [-71.6, 43.9], label: [926, 72] },
    MA: { anchor: [-71.8, 42.25], label: [966, 125] },
    RI: { anchor: [-71.5, 41.65], label: [966, 165] },
    CT: { anchor: [-72.7, 41.6], label: [966, 205] },
    NJ: { anchor: [-74.5, 40.1], label: [966, 245] },
    DE: { anchor: [-75.5, 39.0], label: [966, 285] },
    MD: { anchor: [-76.7, 39.0], label: [966, 325] },
    DC: { anchor: [-77.04, 38.91], label: [966, 365] }
  };

  // A geographic centroid can fall outside a narrow or multipart state.
  var labelAnchors = {
    FL: [-81.8, 28.0], MI: [-84.6, 43.5], LA: [-92.3, 31.0],
    NY: [-75.5, 43.0]
  };

  function stateCode(feature) {
    return FIPS_TO_USPS[String(feature.id).padStart(2, "0")];
  }

  d3.json(geometryUrl).then(function (us) {
    // Fit only the contiguous states and DC to match the supplied reference.
    var states = topojson.feature(us, us.objects.states).features.filter(function (feature) {
      var code = stateCode(feature);
      return code && code !== "AK" && code !== "HI";
    });
    var projection = d3.geoAlbersUsa().fitExtent(
      [[15, 20], [900, 610]],
      { type: "FeatureCollection", features: states }
    );
    var path = d3.geoPath(projection);
    var svg = d3.create("svg")
      .attr("viewBox", "0 0 1000 640")
      .attr("class", "district-visit-map__svg")
      .attr("role", "img")
      .attr("aria-labelledby", "district-visit-map-title district-visit-map-description");

    svg.append("title")
      .attr("id", "district-visit-map-title")
      .text("2026 Congressional District Visits");
    svg.append("desc")
      .attr("id", "district-visit-map-description")
      .text(visitedStates.size + " states with visits are highlighted in SNAP blue. " +
        "Other states are light gray. Expand the state list below for all participating states.");

    var statePaths = svg.append("g").selectAll("path").data(states).join("path")
      .attr("d", path)
      .attr("data-state", stateCode)
      .attr("class", function (feature) {
        return "district-visit-map__state" +
          (visitedStates.has(stateCode(feature)) ? " district-visit-map__state--active" : "");
      });
    statePaths
      .append("title")
      .text(function (feature) {
        return feature.properties.name +
          (visitedStates.has(stateCode(feature)) ? " — visits recorded" : " — no recorded visits");
      });

    // Draw leaders before labels so the text stays legible at their endpoints.
    var leaders = svg.append("g").attr("aria-hidden", "true");
    Object.keys(callouts).forEach(function (code) {
      var callout = callouts[code];
      var anchor = projection(callout.anchor);
      var label = callout.label;
      var endpoint = [label[0] - 18, label[1]];
      if (code === "VT") endpoint = [label[0], label[1] + 14];
      leaders.append("path")
        .attr("class", "district-visit-map__leader")
        .attr("d", "M" + anchor.join(",") + "L" + endpoint.join(","));
    });

    var labels = svg.append("g").attr("aria-hidden", "true")
      .selectAll("text").data(states).join("text")
      .attr("transform", function (feature) {
        var code = stateCode(feature);
        var point = callouts[code] ? callouts[code].label :
          (labelAnchors[code] ? projection(labelAnchors[code]) : path.centroid(feature));
        return "translate(" + point.join(",") + ")";
      })
      .attr("class", function (feature) {
        var code = stateCode(feature);
        return "district-visit-map__label" +
          (visitedStates.has(code) && !callouts[code] ? " district-visit-map__label--active" : "");
      })
      .text(stateCode);

    // Keep the text fallback until the complete map is ready, including on
    // network failure. The independent state list also works without JavaScript.
    container.replaceChildren(svg.node());
  }).catch(function (error) {
    console.error("district-visits-map: could not load state boundaries", error);
  });
}());
