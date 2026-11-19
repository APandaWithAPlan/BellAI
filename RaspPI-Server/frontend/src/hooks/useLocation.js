import { useState, useEffect } from "react";
import { toast } from "@/components/ui/toast"

export function useLocation() {
    const [location, setLocation] = useState(null);

    useEffect(() => {
        let active = true;

        async function fetchLocation() {
            try {
                const response = await fetch("/api/location");

                if(!response.ok) {
                    throw new Error("Failed to fetch /api/location.");
                }

                const data = await response.json();

                if (active) {
                setLocation(data);
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

        fetchLocation();

        return () => {
            active = false;
        };
    }, []);

    return { location };
}