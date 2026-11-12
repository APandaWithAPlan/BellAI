import { useState, useEffect } from "react";
import { toast } from "@/components/ui/toast"

export function useDeviceWebsockets() {
    const [devices, setDevices] = useState([]);

    useEffect(() => {

        const socket = new WebSocket(`ws://${window.location.host}/ws/devices`);

        socket.onmessage = (event) => {
            const data = JSON.parse(event.data);

            setDevices(prev => ({
                ...prev,
                [data.entity_id]: data.new_state
            }));
        };

        socket.onerror = (error) => {
            toast.add({
                type: "error",
                description: error.message
            });
        };

        return () => {
            socket.close();
        };
    }, []);

    return devices;
}