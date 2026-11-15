import { useState, useEffect } from "react";
import { toast } from "@/components/ui/toast";

export function useDeviceWebsockets() {
    const [devices, setDevices] = useState({});

    useEffect(() => {
        let active = true;
        let socket;
        let reconnectTimer;
        let revision = 0;
        const latestRevision = new Map();
        const wsUrl = `ws://${window.location.host}/ws/devices`;

        async function fetchDevices() {
            const snapshotRevision = revision;

            try {
                const response = await fetch("/api/devices");

                if (!response.ok) {
                    throw new Error("Failed to fetch /api/devices.");
                }

                const data = await response.json();

                if (!active) return;

                setDevices(prev => {
                    const initialDevices = Object.fromEntries(
                        data.map(device => [
                            device.entity_id,
                            device
                        ])
                    );

                    for (const [entityId, version] of latestRevision) {
                        if (version > snapshotRevision) {
                            if (entityId in prev) {
                                initialDevices[entityId] = prev[entityId];
                            } else {
                                delete initialDevices[entityId];
                            }
                        }
                    }

                    return initialDevices;
                });

            } catch (error) {
                if (active) {
                    toast.add({
                        type: "error",
                        description: error.message
                    });
                }
            } 
        }

        function connect() {
            socket = new WebSocket(wsUrl);
            let closeWhenOpen = false;

            socket.onopen = () => {
                if (closeWhenOpen || !active) {
                    socket.close();
                    return;
                }

                fetchDevices();
            };

            socket.onmessage = (event) => {
                if (!active) return;

                const data = JSON.parse(event.data);

                if (!data.entity_id) return;

                revision += 1;
                latestRevision.set(data.entity_id, revision);

                setDevices(prev => {
                    if (data.new_state === null) {
                        const updated = { ...prev };
                        delete updated[data.entity_id];
                        return updated;
                    }

                    return {
                        ...prev,
                        [data.entity_id]: data.new_state
                    };
                });
            };

            socket.onerror = () => {
                if (active) {
                    console.error("Unable to connect to Websocket server.");
                }
            };

            socket.onclose = () => {
                if (active) {
                    reconnectTimer = setTimeout(connect, 3000);
                }
            };

            socket.cleanup = () => {
                closeWhenOpen = true;

                if (socket.readyState === WebSocket.OPEN) {
                    socket.close();
                }
            };
        }

        connect();

        return () => {
            active = false;
            clearTimeout(reconnectTimer);

            if (socket) {
                socket.cleanup();
            }
        };
    }, []);

    return { devices };
}
