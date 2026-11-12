import { useState, useEffect } from "react";
import { toast } from "@/components/ui/toast"
import { useDeviceCommand } from "./useDeviceCommand";

export function useDevices() {
    const [devices, setDevices] = useState([])

    useEffect(() => {
        let active = true;

        async function fetchDevices() {
            try {
                const response = await fetch("/api/devices");

                    if (!response.ok) {
                        throw new Error("Failed to fetch /api/devices.");
                    }

                const data = await response.json();

                if (active) {
                    setDevices(data);
                }

            } catch (error) {

                if (active) {
                    toast.add({
                        type: "warning",
                        description: error.message
                    });
                }
            }
        }

        fetchDevices();

        return () => {
            active = false;
        };
    }, []);

    async function toggleDevice(entity_id, checked) {
        const action = checked ? "turn_on" : "turn_off";
        const domain = entity_id.split(".")[0];

        try {
            await commandDevice(entity_id, domain, action);

            setDevices(prevDevices =>
                prevDevices.map(device =>
                    device.entity_id === entity_id
                    ? { ...device, staten: checked ? "on" : "off"}
                    : device
                )
            );
        } catch (error) {
            toast.add({
                type: "error",
                description: error.message
            });
        }
    }

    return { devices, toggleDevice };
}