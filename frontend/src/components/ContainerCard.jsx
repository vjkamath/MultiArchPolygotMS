import React from "react";
import "./ContainerCard.css";

const ContainerCard = ({ container }) => {
  const getArchitectureColor = (arch) => {
    return arch === "arm64" ? "#4CAF50" : "#2196F3";
  };

  const getMemoryUsage = (memory) => {
    return ((memory.used / memory.total) * 100).toFixed(2);
  };

  return (
    <div className="container-card">
      <div
        className="architecture-badge"
        style={{
          backgroundColor: getArchitectureColor(container.architecture),
        }}
      >
        {container.architecture}
      </div>
      <h3>{container.service}</h3>
      <div className="metrics">
        <div className="metric-item">
          <label>CPU Usage:</label>
          <span>{container.cpu}%</span>
        </div>
        <div className="metric-item">
          <label>Memory:</label>
          <span>{getMemoryUsage(container.memory)}%</span>
        </div>
        <div className="metric-item">
          <label>Platform:</label>
          <span>{container.platform}</span>
        </div>
        <div className="metric-item">
          <label>Status:</label>
          <span className={`status ${container.status.toLowerCase()}`}>
            {container.status}
          </span>
        </div>
      </div>
    </div>
  );
};

export default ContainerCard;
