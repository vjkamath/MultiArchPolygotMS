import React, { useEffect, useRef } from "react";
import * as d3 from "d3";
import "./ArchitectureGraph.css";

const ArchitectureGraph = ({ containers }) => {
  const svgRef = useRef();

  useEffect(() => {
    if (!containers.length) return;

    const width = 600;
    const height = 400;
    const margin = { top: 20, right: 20, bottom: 30, left: 40 };

    // Clear previous graph
    d3.select(svgRef.current).selectAll("*").remove();

    // Process data
    const architectures = containers.reduce((acc, container) => {
      acc[container.architecture] = (acc[container.architecture] || 0) + 1;
      return acc;
    }, {});

    const data = Object.entries(architectures).map(([arch, count]) => ({
      architecture: arch,
      count: count,
    }));

    // Create SVG
    const svg = d3
      .select(svgRef.current)
      .attr("width", width)
      .attr("height", height);

    // Create scales
    const x = d3
      .scaleBand()
      .range([margin.left, width - margin.right])
      .padding(0.1)
      .domain(data.map((d) => d.architecture));

    const y = d3
      .scaleLinear()
      .range([height - margin.bottom, margin.top])
      .domain([0, d3.max(data, (d) => d.count)]);

    // Add bars
    svg
      .selectAll("rect")
      .data(data)
      .enter()
      .append("rect")
      .attr("x", (d) => x(d.architecture))
      .attr("y", (d) => y(d.count))
      .attr("width", x.bandwidth())
      .attr("height", (d) => height - margin.bottom - y(d.count))
      .attr("fill", (d) =>
        d.architecture === "arm64" ? "#4CAF50" : "#2196F3"
      );

    // Add axes
    svg
      .append("g")
      .attr("transform", `translate(0,${height - margin.bottom})`)
      .call(d3.axisBottom(x));

    svg
      .append("g")
      .attr("transform", `translate(${margin.left},0)`)
      .call(d3.axisLeft(y));

    // Add title
    svg
      .append("text")
      .attr("x", width / 2)
      .attr("y", margin.top)
      .attr("text-anchor", "middle")
      .text("Container Architecture Distribution");
  }, [containers]);

  return (
    <div className="architecture-graph">
      <svg ref={svgRef}></svg>
    </div>
  );
};

export default ArchitectureGraph;
