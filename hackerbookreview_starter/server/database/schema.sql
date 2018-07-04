begin;
create schema hb;

create table hb.author (
  id                serial primary key,
  name              text,
  created_at        timestamp default now()
);

comment on table hb.author is 'A book author.';
comment on column hb.author.id is 'The primary unique identifier for the author.';
comment on column hb.author.name is 'The author''s name.';
comment on column hb.author.created_at is 'The time this author was created.';

create table hb.book (
  id                serial primary key,
  google_id         text unique,
  title             text not null,
  subtitle          text,
  description       text,
  page_count        int default 0,
  rating_total      int default 0,
  rating_count      int default 0,
  rating            decimal default 0,
  created_at        timestamptz default now()
);

create index book_google_id_idx on hb.book(google_id);

comment on table hb.book is 'A book.';
comment on column hb.book.id is 'The primary unique identifier for the book.';
comment on column hb.book.title is 'The books title.';
comment on column hb.book.subtitle is 'The books subtitle.';
comment on column hb.book.description is 'The books description.';
comment on column hb.book.page_count is 'The number of pages in the book.';
comment on column hb.book.rating_total is 'The total number of all the user reviews for the book. ie user1: 4 star, user2: 5 star, user3: 3 star => review_total = 12 (4 + 5 + 3)';
comment on column hb.book.rating_count is 'The count of all the user reviews for the book. ie user1: 4 star, user2: 5 star, user3: 3 star => review_count = 3';
comment on column hb.book.rating is 'The average rating for the book';
comment on column hb.book.created_at is 'The time this book was created.';

create table hb.book_author(
  id                serial primary key,
  book_id           int not null references hb.book(id),
  author_id         int not null references hb.author(id),
  created_at        timestamp default now()
);

create index book_author_book_id_idx on hb.book_author(book_id);
create index book_author_author_id_idx on hb.book_author(author_id);

comment on table hb.book_author is 'A book author.';
comment on column hb.book_author.id is 'The primary unique identifier for the book.';
comment on column hb.book_author.book_id is 'The id for the book.';
comment on column hb.book_author.author_id is 'The id for the author.';
comment on column hb.book_author.created_at is 'The time this book author was created.';

create table hb.person (
  id                serial primary key,
  email             text unique not null check (email ~* '^.+@.+\..+$'),
  name              text not null,
  created_at        timestamp default now()
);

comment on table hb.person is 'A book reviewer.';
comment on column hb.person.id is 'The primary unique identifier for the person.';
comment on column hb.person.name is 'The person''s name.';
comment on column hb.person.email is 'The person''s email.';
comment on column hb.person.created_at is 'The time this person was created.';

create table hb.review(
  id                serial primary key,
  person_id         int not null references hb.person(id),
  rating            int not null check(rating >= 1 and rating <= 5),
  title             text,
  comment           text,
  created_at        timestamptz default now()
);

create index review_person_id_idx on hb.review(person_id);

comment on table hb.review is 'A book review.';
comment on column hb.review.person_id is 'The id of the person doing the review';
comment on column hb.review.rating is 'The number of stars given 1-5';
comment on column hb.review.title is 'The review title left by the person';
comment on column hb.review.comment is 'The review comment left by the person';
comment on column hb.review.created_at is 'The time this review was created.';

create table hb.book_review(
  id                serial primary key,
  book_id           int not null references hb.book(id),
  review_id         int not null references hb.review(id)
);

create index book_review_book_id_idx on hb.book_review(book_id);
create index book_review_review_id_idx on hb.book_review(review_id);

comment on table hb.book_review is 'A book_review.';
comment on column hb.book_review.id is 'The primary unique identifier for the book review.';
comment on column hb.book_review.book_id is 'The id of the book being reviewed';
comment on column hb.book_review.review_id is 'The id of the book review';

create function hb.create_book(
  google_book_id        text,
  title                 text, 
  subtitle              text,
  description           text,
  authors               text[],
  page_count            integer
) returns hb.book as $$
declare
  book            hb.book;
  authors_rows    hb.author[];
  author_ids      int[];
begin

  select * from hb.book where hb.book.google_id = google_book_id into book;

  if book.id > 0 then
    return book;
  else
    insert into hb.book(google_id, title, subtitle, description, page_count)
      values (google_book_id, title, subtitle, description, page_count) 
      returning * into book;

    with ai as (
      insert into hb.author(name) select unnest(authors) 
        returning id 
    ) 

    insert into hb.book_author(book_id, author_id) 
    select book.id, id from ai;

    return book;
  end if;
end;
$$ language plpgsql strict security definer;

comment on function hb.create_book(text, text, text, text, text[], integer) is 'creates a book.';

create function hb.create_review(
  book_id         integer,
  reviewer_email  text,
  name            text,
  new_rating      integer,
  title           text,
  comment         text
) returns hb.review as $$
declare
  person_id     integer;
  review        hb.review;
begin
  insert into hb.person(email, name) 
    values (reviewer_email, name) 
    on conflict (email) do nothing;

  select id into person_id from hb.person where email = reviewer_email;  

  insert into hb.review(person_id, rating, title, comment) 
    values(person_id, new_rating, title, comment) 
    returning * into review;

  insert into hb.book_review(book_id, review_id)
    values(book_id, review.id);

  update hb.book set 
    rating_total = rating_total + new_rating, 
    rating_count = rating_count + 1, 
    rating = (rating_total + new_rating) / (rating_count  + 1)
    where id = book_id;

  return review;
end;
$$ language plpgsql strict security definer;

comment on function hb.create_review(integer, text, text, integer, text, text) is 'creates a book review.';

commit;