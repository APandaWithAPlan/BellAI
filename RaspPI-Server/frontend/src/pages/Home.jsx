import DateTimeCard from "../components/DateTimeCard"
import WeatherCard from "../components/WeatherCard"

function Home() {
    return (
        <div className="grid grid-cols-4 gap-4">

            <div className="col-span-3">
            <DateTimeCard time="7:50" date="SUNDAY, OCTOBER 25" period="PM" />
            </div>

            <div className="col-span-1">
                <WeatherCard temperature="50" description="Partly Cloudy" high="72" low="56" hum="62" location="San Francisco, CA" />
            </div>

        </div>  
    )
}

export default Home