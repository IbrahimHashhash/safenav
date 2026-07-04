// SafeNav — Azure Custom Speech structured-text training data
// Format: Custom Speech "structured text" (Markdown). Locale: en-US.
// Save this file as UTF-8 with BOM before uploading (Speech Studio requirement).
//
// Lists are defined with @list and referenced inside training sentences as
// {@listName}. Sections start with '#'. Comments start with '//'.
// Limits: up to 20 lists, 35,000 items per list, file <= 200 MB.

// ---------------------------------------------------------------------------
// LISTS
// ---------------------------------------------------------------------------

@list place =
- faculty of engineering and information technology
- faculty of engineering
- faculty of science
- faculty of business and economics
- faculty of arts
- faculty of education
- faculty of law
- faculty of health professions
- faculty of media
- faculty of sports
- faculty of art and design
- faculty of women studies
- shawqi shaheen building
- building for development studies
- al sadik
- kamal nasir library

@list category =
- faculties
- libraries
- cafeterias
- landmarks

@list name =
- mohammed
- ahmad
- mahmoud
- omar
- ali
- khaled
- yousef
- ibrahim
- ismail
- hamza
- hassan
- hussein
- bilal
- tariq
- rami
- samir
- waleed
- zaid
- anas
- saif
- laith
- yazan
- qusai
- adam
- kareem
- bashar
- suhaib
- obada
- khalil
- mustafa
- abdullah
- abdelrahman
- sara
- layla
- fatima
- maryam
- noor
- huda
- rana
- lina
- dina
- nour
- yara
- zaina
- aya
- salma
- hala
- reem
- dana
- jana
- lana
- malak
- raghad
- batool
- mays
- raheeq
- adel
- ma'moun 

// Optional phonetic hints for proper nouns the model may mishear. These use
// the Universal Phone Set; treat them as STARTING POINTS and verify/adjust in
// Speech Studio. Remove any you are unsure about — a wrong phoneme can hurt.
@speech:phoneticlexicon
- shawqi/sh aw k iy
- nasir/n aa s ih r
- sadik/s aa d ih k
- yousef/y uw s ih f
- mahmoud/m ah m uw d

// ---------------------------------------------------------------------------
// TRAINING SENTENCES
// ---------------------------------------------------------------------------

#Commands
- start detection
- stop detection
- start obstacle detection
- stop obstacle detection
- begin detection
- begin obstacle detection
- enable detection
- disable detection
- turn on detection
- turn off detection
- start navigation
- stop navigation
- begin navigation
- cancel navigation
- end navigation
- repeat
- repeat that
- say that again
- next
- next instruction
- continue
- more info
- what can you do
- what can i say
- change my name
- update my name
- rename me

#Navigation
- navigate to the {@place}
- navigate to {@place}
- take me to the {@place}
- take me to {@place}
- go to the {@place}
- go to {@place}
- i want to go to the {@place}
- i need to get to the {@place}
- directions to the {@place}
- how do i get to the {@place}
- guide me to the {@place}
- where is the {@place}
- start navigation to the {@place}

#ListPlaces
- list places
- list locations
- list {@category}
- show me the {@category}
- what {@category} are available
- what {@category} are there
- give me the list of {@category}

#Naming
- my name is {@name}
- the name is {@name}
- call me {@name}
- you can call me {@name}
- i am {@name}
- i'm {@name}
- this is {@name}
- {@name}

#Greetings
- hello
- hi
- hey
- good morning
- good afternoon
- good evening
