import EventCard from "../components/EventCard"
import EmailCard from "../components/EmailCard"
import ToDoCard from "../components/ToDoCard"
import DeliveriesCard from "../components/DeliveriesCard"
import { Calendar, Mail, Check, Box } from "lucide-react"

function Life() {

    return (
        <div className="flex flex-col gap-6">

            <section className="flex flex-col gap-3">
                <h3 className="flex items-center gap-2 text-xs text-[#a35b89]">
                    <Calendar size={16} strokeWidth={1.5}/> 
                    Today's Schedule
                </h3>

                <div className="flex flex-col gap-2">         
                    <EventCard time="9:30 AM" timeUntil="30 min" title="Team Standup"/>
                    <EventCard time="12:30 PM" timeUntil="1 hour" title="Lunch with Marco"/>
                    <EventCard time="3:00 PM" timeUntil="45 min" title="Dentist Appointment"/>
                </div>
            </section>

            <section className="flex flex-col gap-3">
                <div className="flex items-center justify-between">
                    <h3 className="flex items-center gap-2 text-xs text-[#a35b89]">
                        <Mail size={16} strokeWidth={1.5}/> 
                        Flagged Emails
                    </h3>
                </div>

                <div className="flex flex-col gap-2">
                    <EmailCard sender="Sarah M." subject="Weekend plans — are you in?" contents="Hey! We were thinking Sunday brunch at that new place on Valencia..." time="7:41 AM"/>
                    <EmailCard sender="Marco Chen" subject="Project Alpha — quick update" contents="The client approved the revised scope. We need to reconvene before..." time="6:58 AM"/>
                    <EmailCard sender="Amazon" subject="Your package is arriving today" contents="Track your delivery — estimated between 2:00–6:00 PM" time="yesterday"/>
                </div>
            </section>        
        
            <section className="flex flex-col gap-3">
                <h3 className="flex items-center gap-2 text-xs text-[#a35b89]">
                    <Check size={16} strokeWidth={1.5}/> 
                    To-Do
                </h3>

                <div className="flex flex-col gap-2"> 
                    <ToDoCard task="Call the vet about Luna's checkup"/>
                    <ToDoCard task="Order birthday gift for Mom"/>
                    <ToDoCard task="Review Q3 report before Thursday"/>
                    <ToDoCard task="Pick up dry cleaning"/>
                    <ToDoCard task="Schedule HVAC maintenance"/>
                </div>
            </section>

            <section className="flex flex-col gap-3">
                <h3 className="flex items-center gap-2 text-xs text-[#a35b89]">
                    <Box size={16} strokeWidth={1.5}/> 
                    Deliveries
                </h3>

                <div className="flex flex-col gap-2">
                    <DeliveriesCard seller="Amazon" item="Echo Pop (2-pack)" arrivalTime="Today, 2-6 PM" progress={80}/>
                    <DeliveriesCard seller="Apple Store" item="AirPods Pro 3" arrivalTime="2 days" progress={50}/>
                </div>
            </section>

        </div> 
    )
}

export default Life