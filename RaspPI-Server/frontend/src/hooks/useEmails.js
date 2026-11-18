import { useState, useEffect, useMemo } from "react";
import { toast } from "@/components/ui/toast";
import { getDeliveries } from "./useDeliveryEmails";
import { getImportantEmails } from "./useImportantEmails";
import { getTodayEvents } from "./useTodayEvents";

export function useEmails() {
    const [emails, setEmails] = useState([]);

    useEffect(() => {
        let active = true;

        async function fetchEmails() {
            try {
                const response = await fetch("/api/mail?limit=100");

                if (!response.ok) {
                    throw new Error("Failed to fetch /api/mail.");
                }

                const data = await response.json();

                if (active) {
                    setEmails(data.mail);
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

        fetchEmails();

        const interval = setInterval(fetchEmails, 3 * 60 * 1000);

        return () => {
            active = false;
            clearInterval(interval);
        };
    }, []);

    const today_events = useMemo(() => getTodayEvents(emails), [emails]);
    const important_emails = useMemo(() => getImportantEmails(emails), [emails]);
    const delivery_emails = useMemo(() => getDeliveries(emails), [emails]);

    return {today_events, important_emails, delivery_emails };
}