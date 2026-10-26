import DateTimeCard from "../components/DateTimeCard"

function Home() {
    return (
        <div className="grid grid-cols-2 gap-4">
            <DateTimeCard time="7:50" date="SUNDAY, OCTOBER 25" period="PM" />
        </div>  
    )
}

export default Home