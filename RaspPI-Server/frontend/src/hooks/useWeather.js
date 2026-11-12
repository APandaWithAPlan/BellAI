import { useState, useEffect } from "react";
import { toast } from "@/components/ui/toast"

export function useWeather() {
    const [weather, setWeather] = useState(null);
    
    useEffect(() => {
        let active = true;

        async function fetchWeather() {
            try {
                const response = await fetch("/api/weather");

                if(!response.ok) {
                    throw new Error("Failed to fetch /api/weather.");
                }

                const data = await response.json();

                if (active) {
                setWeather(data);
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

        fetchWeather();

        return () => {
            active = false;
        };
    }, []);

    return { weather };
}