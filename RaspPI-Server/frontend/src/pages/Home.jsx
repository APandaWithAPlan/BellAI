import DateTimeCard from "../components/DateTimeCard"
import { useDateTime } from "../hooks/useDateTime"
import WeatherCard from "../components/WeatherCard"
import DeviceCard from "../components/DeviceCard"
import MusicCard from "../components/MusicCard"
import EventCard from "../components/EventCard"
import { Lightbulb, Thermometer, Lock, Mic } from "lucide-react"
import { useState, useEffect } from "react";
import { toast } from "@/components/ui/toast"

function Home() {

    const { date, time, period } = useDateTime();
    const [weather, setWeather] = useState(null);
    const [location, setLocation] = useState(null);

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
    
    return (
        <div className="grid grid-cols-4 gap-4">

            <div className="col-span-3">
                <DateTimeCard time={time} date={date} period={period} />
            </div>

            <div className="col-span-1">
                {weather && location ? (
                <WeatherCard temperature={weather.temperature} temperature_unit={weather.temperature_unit} description={weather.description} high={weather.high} low={weather.low} hum={weather.humidity} location={`${location.city}, ${location.state}`} />
                ) : ( <p></p>
                )}
            </div>

            <DeviceCard
                icon={Lightbulb}
                value="6 Lights"
                label="Active"
                color="#ef6cba"
            />

            <DeviceCard
                icon={Thermometer}
                value="85°F"
                label="Thermostat"
                color="#54b7e8"
            />

            <DeviceCard
                icon={Lock}
                value="Locked"
                label="Doors"
                color="#37c5a1"
            />

            <DeviceCard
                icon={Mic}
                value="Ask BellAI"
                label="Voice"
                color="#ef6cba"
            />

            <div className="col-span-4">
                <MusicCard song="Blonde" artist="Frank Ocean" device="Living Room Speaker" />
            </div>

            <div className="col-span-4">
                <EventCard time="9:30 AM" timeUntil="30 min" title="Team Standup" />
            </div>

        </div>  
    )
}

export default Home