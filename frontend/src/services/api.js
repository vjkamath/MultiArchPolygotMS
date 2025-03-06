const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || "";

export const fetchContainerInfo = async () => {
  try {
    const [nodejsResponse, pythonResponse] = await Promise.all([
      fetch(`${API_BASE_URL}/api/containers`),
      fetch(`${API_BASE_URL}/api/metrics`),
    ]);

    const nodejsData = await nodejsResponse.json();
    const pythonData = await pythonResponse.json();

    return [...nodejsData, pythonData];
  } catch (error) {
    console.error("Error fetching container info:", error);
    throw error;
  }
};
