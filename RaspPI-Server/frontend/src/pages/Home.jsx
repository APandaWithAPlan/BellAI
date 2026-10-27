import DateTimeCard from "../components/DateTimeCard"
import WeatherCard from "../components/WeatherCard"
import DeviceCard from "../components/DeviceCard"
import MusicCard from "../components/MusicCard"
import EventCard from "../components/EventCard"
import { Lightbulb, Thermometer, Lock, Mic } from "lucide-react"
import { NavLink } from "react-router"

function Home() {
    return (
        <div className="grid grid-cols-4 gap-4">

            <div className="col-span-3">
                <DateTimeCard time="7:50" date="SUNDAY, OCTOBER 25" period="PM" />
            </div>

            <div className="col-span-1">
                <WeatherCard temperature="50" description="Partly Cloudy" high="72" low="56" hum="62" location="San Francisco, CA" />
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
                <EventCard time="9:30 AM" timeUntil="30" title="Team Standup" />
            </div>

        </div>  
    )
}

export default Home