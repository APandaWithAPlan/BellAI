import { toast } from "@/components/ui/toast"

export function useDeviceCommand() {

    async function commandDevice(entity_id, domain, action, data = {}) {

        try {
            const response = await fetch("/api/device/command", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json"
                },
                body: JSON.stringify({
                    entity_id,
                    domain,
                    action,
                    data
                })
            });

            if (!response.ok) {
                throw new Error(`Failed to control ${device}`);
            }

            return await response.json();

        } catch (error) {
            toast.add({
                type: "error",
                description: error.message
            });
        }
    }

    return { commandDevice }
}