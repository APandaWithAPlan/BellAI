import { toast } from "@/components/ui/toast"
import { useDeviceCommand } from "./useDeviceCommand";
import { useDeviceWebsockets } from "./useDeviceWebsockets";

export function useToggleDevice() {
    const { devices } = useDeviceWebsockets();
    const { commandDevice } = useDeviceCommand();

    async function toggleDevice(entity_id, checked) { 
        
        const device = devices[entity_id];

        if (device?.state === "unavailable" || device?.state === "unknown") {
            toast.add({
                type: "error",
                description: `${device.name} is unavailable.`
            });
            return;
        }

        const action = checked ? "turn_on" : "turn_off";
        const domain = entity_id.split(".")[0];

        try {
            await commandDevice(entity_id, domain, action);
            toast.add({
                type: "success",
                description: checked ? `${device.name} is on.` : `${device.name} is off.`
            });

        } catch (error) {
            toast.add({
                type: "error",
                description: error.message
            });
        }
    }

    return { devices, toggleDevice };
}