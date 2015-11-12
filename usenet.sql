CREATE LANGUAGE 'plpgsql';

DROP TABLE usenet_article;
DROP TABLE usenet_binary;
DROP TABLE usenet_newsgroup;

CREATE TABLE usenet_newsgroup (
    id serial NOT NULL,
    name varchar(254) NOT NULL,
    PRIMARY KEY(id)
);

CREATE UNIQUE INDEX usenet_newsgroup_name_idx ON usenet_newsgroup(name);

CREATE TABLE usenet_binary (
    id serial NOT NULL,
    name varchar(254) NOT NULL,
    posted timestamp NOT NULL,
    PRIMARY KEY(id)    
);

CREATE TABLE usenet_article (
    id bigserial NOT NULL,
    article integer NOT NULL,
    message varchar(254) NOT NULL,
    subject text NOT NULL,
    posted timestamp NOT NULL,
    newsgroup_id integer NOT NULL,
    binary_id integer,
    PRIMARY KEY(id),
    FOREIGN KEY(newsgroup_id) REFERENCES usenet_newsgroup(id),
    FOREIGN KEY(binary_id) REFERENCES usenet_binary(id)
);

CREATE UNIQUE INDEX usenet_article_message_idx ON usenet_article(message);
CREATE UNIQUE INDEX usenet_article_newsgroup_article_idx ON usenet_article(newsgroup_id, article);
CREATE INDEX usenet_article_bin_idx ON usenet_article(binary_id);
