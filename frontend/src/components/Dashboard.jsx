import React, { useState, useEffect } from "react";
import ContainerCard from "./ContainerCard";
import ArchitectureGraph from "./ArchitectureGraph";

const Dashboard = () => {
  const [containers, setContainers] = useState([]);

  useEffect(() => {
    const fetchContainers = async () => {
      const response = await fetch("/api/containers");
      const data = await response.json();
      setContainers(data);
    };

    fetchContainers();
    const interval = setInterval(fetchContainers, 30000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="dashboard">
      <h1>Polyglot Architecture Demo</h1>
      <ArchitectureGraph containers={containers} />
      <div className="container-grid">
        {containers.map((container) => (
          <ContainerCard key={container.id} container={container} />
        ))}
      </div>
    </div>
  );
};

export default Dashboard;
