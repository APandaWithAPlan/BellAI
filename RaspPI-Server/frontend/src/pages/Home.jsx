import DateTimeCard from "../components/DateTimeCard"
import { useDateTime } from "../hooks/useDateTime"
import WeatherCard from "../components/WeatherCard"
import { useWeather } from "../hooks/useWeather"
import { useLocation } from "../hooks/useLocation"
import DeviceCard from "../components/DeviceCard"
import MusicCard from "../components/MusicCard"
// import { useDevices } from "../hooks/useDevices"
import { useDeviceWebsockets } from "../hooks/useDeviceWebsockets"
import EventCard from "../components/EventCard"
import { Lightbulb, Thermometer, Lock, Cog } from "lucide-react"

function Home() {

    const { date, time, period } = useDateTime();
    const { weather } = useWeather();
    const { location } = useLocation();
    const { devices } = useDeviceWebsockets();
    const activeLights = devices.filter(device => device.entity_id.startsWith("light") && device.state === "on").length;
    const media_players = devices.filter(device => device.entity_id.startsWith("media_player."));
    
    return (
        <div className="grid grid-cols-4 gap-4">

            <div className="col-span-3">
                <DateTimeCard time={time} date={date} period={period} />
            </div>

            <div className="col-span-1">
                {weather && location ? (
                <WeatherCard temperature={weather.temperature} temperature_unit={weather.temperature_unit} description={weather.description} high={weather.high} low={weather.low} hum={weather.humidity} location={`${location.city}, ${location.state}`} />
                ) : ( <WeatherCard temperature="" temperature_unit="" description="" high="" low="" hum="" location="" />
                )}
            </div>

            <DeviceCard
                icon={Lightbulb}
                value={`${activeLights} Lights`}
                label="Active"
                color="#ef6cba"
            />

            <DeviceCard
                icon={Thermometer}
                value="Unavailable"
                label="Thermostat"
                color="#54b7e8"
            />

            <DeviceCard
                icon={Lock}
                value="Unavailable"
                label="Doors"
                color="#37c5a1"
            />

            <DeviceCard
                icon={Cog}
                value="Unavailable"
                label="Sensors"
                color="#ef6cba"
            />

            <div className="col-span-4"> 
                {media_players.map(media_player => (
                    <MusicCard 
                        key={media_player.entity_id}
                        entity_id={media_player.entity_id}
                        device={media_player.name}
                        song={media_player.attributes.media_title}
                        artist={media_player.attributes.media_artist}
                        isPlaying={media_player.state === "playing"}
                    />
                ))}
            </div>

            <div className="col-span-4">
                <EventCard time="9:30 AM" timeUntil="30 min" title="Team Standup" />
            </div>

        </div>  
    )
}

export default Home