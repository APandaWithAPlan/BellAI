import EventCard from "../components/EventCard"
import EmailCard from "../components/EmailCard"
import ToDoCard from "../components/ToDoCard"
import DeliveriesCard from "../components/DeliveriesCard"
import { useEmails } from "../hooks/useEmails"
import { useTasks } from "../hooks/useTasks"
import { Calendar, Mail, Check, Box } from "lucide-react"

function Life() {

    const { today_events, important_emails, delivery_emails } = useEmails();
    const { tasks } = useTasks();

    return (
        <div className="flex flex-col gap-6">

            <section className="flex flex-col gap-3">
                <h3 className="flex items-center gap-2 text-xs text-[#be185d]">
                    <Calendar size={16} strokeWidth={1.5}/> 
                    Today's Schedule
                </h3>

                <div className="flex flex-col gap-2"> 
                            
                    {today_events.length > 0 ? (
                        today_events.map((event) => (
                        <EventCard
                            key={event.id}
                            subject={event.subject}
                            due={event.due}
                        />
                        ))
                    ) : (
                        <p className="text-sm text-black/50">
                            No events scheduled for today. 
                        </p>
                    )}

                    {/* <EventCard time="9:30 AM" timeUntil="30 min" title="Team Standup"/>
                    <EventCard time="12:30 PM" timeUntil="1 hour" title="Lunch with Marco"/>
                    <EventCard time="3:00 PM" timeUntil="45 min" title="Dentist Appointment"/> */}
                </div>
            </section>

            <section className="flex flex-col gap-3">
                <div className="flex items-center justify-between">
                    <h3 className="flex items-center gap-2 text-xs text-[#be185d]">
                        <Mail size={16} strokeWidth={1.5}/> 
                        Flagged Emails
                    </h3>
                </div>

                <div className="flex flex-col gap-2">
                    {important_emails.length > 0 ? (
                        important_emails.map((email) => (
                            <EmailCard
                                key={email.id}
                                sender={email.sender}
                                subject={email.subject}
                                summary={email.summary}
                            received={email.received}
                        />
                        ))
                    ) : (
                        <p className="text-sm text-black/50">
                            No flagged emails for today.
                        </p>
                    )}
                </div>
            </section>        
        
            <section className="flex flex-col gap-3">
                <h3 className="flex items-center gap-2 text-xs text-[#be185d]">
                    <Check size={16} strokeWidth={1.5}/> 
                    To-Do
                </h3>

                <div className="flex flex-col gap-2"> 
                    {tasks.length > 0 ? (
                        tasks.map((task) => (
                            <ToDoCard
                                key={task.id}   
                                task={task.task}
                            />
                        ))
                    ) : (   
                        <p className="text-sm text-black/50">
                            No tasks for today.
                        </p>
                    )}
                    {/* <ToDoCard task="Call the vet about Luna's checkup"/>
                    <ToDoCard task="Order birthday gift for Mom"/>
                    <ToDoCard task="Review Q3 report before Thursday"/>
                    <ToDoCard task="Pick up dry cleaning"/>
                    <ToDoCard task="Schedule HVAC maintenance"/> */}
                </div>
            </section>

            <section className="flex flex-col gap-3">
                <h3 className="flex items-center gap-2 text-xs text-[#be185d]">
                    <Box size={16} strokeWidth={1.5}/> 
                    Deliveries
                </h3>


                <div className="flex flex-col gap-2">

                    {delivery_emails.length > 0 ? (
                        delivery_emails.map((email) => (
                            <DeliveriesCard
                                key={email.id}
                                sender={email.sender}
                                subject={email.subject}
                                due={email.due}
                            />
                        ))
                    ) : (
                        <p className="text-sm text-black/50">
                            No deliveries scheduled for today.
                        </p>
                    )}
                    {/* <DeliveriesCard seller="Amazon" item="Echo Pop (2-pack)" arrivalTime="Today, 2-6 PM" progress={80}/>
                    <DeliveriesCard seller="Apple Store" item="AirPods Pro 3" arrivalTime="2 days" progress={50}/> */}
                </div>
            </section>

        </div> 
    )
}

export default Life