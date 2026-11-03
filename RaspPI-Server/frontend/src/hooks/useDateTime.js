import { useState, useEffect } from "react";

export function useDateTime() {
    const [dateTime, setDateTime] = useState(new Date());
    
    useEffect(() => {
        const interval = setInterval(()=>setDateTime(new Date()), 1000)
        return function cleanup() {
            clearInterval(interval)
        }
    });

    const date = dateTime.toLocaleDateString("en-US", {
        weekday: "long",
        month: "long",
        day: "numeric",
        year: "numeric"
    });

    const time = dateTime.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true
    }).replace(/\s?[AP]M$/, "");

    const period = (dateTime.getHours() >= 12) ? "PM" : "AM";

    return { date, time, period };
}