import { useState, useEffect } from "react";
import { toast } from "@/components/ui/toast";

export function useTasks() {
    const [tasks, setTasks] = useState([]);

    useEffect(() => {
        let active = true;

        async function fetchTasks() {
            try {
                const response = await fetch("/api/tasks");

                if (!response.ok) {
                    throw new Error("Failed to fetch api/data.");
                }

                const data = await response.json();

                if (active) {
                    setTasks(data.data?.tasks ?? []);
                }

            } catch (error) {
                if (active) {
                    toast.add({
                        type: "error",
                        description: error.message
                    });
                }
            }
        }

        fetchTasks();

        const interval = setInterval(fetchTasks, 3 * 60 * 1000);

        return () => {
            active = false;
            clearInterval(interval);
        };
    }, []);

    return { tasks };
}